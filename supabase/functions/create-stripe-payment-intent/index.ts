import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { enforceGuestRateLimit } from '../_shared/guestRateLimit.ts';

const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Expose-Headers': 'Retry-After' };
const fail = (code: string, message: string, status = 400, extraHeaders: Record<string, string> = {}) => new Response(JSON.stringify({ ok: false, code, message }), { status, headers: { ...headers, ...extraHeaders, 'Content-Type': 'application/json' } });
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const paymentCapabilityPattern = /^[A-Za-z0-9_-]{43}$/;

type PreparedPayment = {
  payment_id: string;
  order_id: string;
  amount_minor: number | string;
  currency_code: string;
  provider_idempotency_key: string;
  provider_payment_intent_id: string | null;
};

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);

const decodePaymentCapability = (value: unknown): Uint8Array | null => {
  if (typeof value !== 'string' || !paymentCapabilityPattern.test(value)) return null;
  try {
    const decoded = atob(value.replace(/-/g, '+').replace(/_/g, '/') + '=');
    if (decoded.length !== 32) return null;
    return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
};

const sha256Hex = async (bytes: Uint8Array): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
};

const readDefaultSecretKey = (): string | null => {
  const rawSecretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (!rawSecretKeys) {
    console.error('create-stripe-payment-intent configuration error: SUPABASE_SECRET_KEYS is missing.');
    return null;
  }
  try {
    const parsed: unknown = JSON.parse(rawSecretKeys);
    const key = isRecord(parsed) ? parsed.default : undefined;
    if (typeof key !== 'string' || key.trim().length === 0) {
      console.error('create-stripe-payment-intent configuration error: SUPABASE_SECRET_KEYS.default is missing or invalid.');
      return null;
    }
    return key.trim();
  } catch {
    console.error('create-stripe-payment-intent configuration error: SUPABASE_SECRET_KEYS is not valid JSON.');
    return null;
  }
};

const toPreparedPayment = (value: unknown): PreparedPayment | null => {
  if (!isRecord(value)
    || typeof value.payment_id !== 'string' || typeof value.order_id !== 'string'
    || typeof value.currency_code !== 'string' || typeof value.provider_idempotency_key !== 'string'
    || (value.provider_payment_intent_id !== null && typeof value.provider_payment_intent_id !== 'string')) return null;
  const amountMinor = Number(value.amount_minor);
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0 || value.currency_code !== 'GBP' || !uuidPattern.test(value.payment_id) || !uuidPattern.test(value.order_id) || !uuidPattern.test(value.provider_idempotency_key)) return null;
  return { ...value, amount_minor: amountMinor } as PreparedPayment;
};

const stripeRequest = async (path: string, stripeSecretKey: string, init: RequestInit): Promise<Record<string, unknown> | null> => {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    ...init,
    headers: { Authorization: `Basic ${btoa(`${stripeSecretKey}:`)}`, ...init.headers }
  });
  if (!response.ok) {
    console.error(`create-stripe-payment-intent Stripe API error: ${response.status}`);
    return null;
  }
  const body: unknown = await response.json().catch(() => null);
  return isRecord(body) ? body : null;
};

const resumablePaymentIntentStatuses = new Set(['requires_payment_method', 'requires_confirmation', 'requires_action']);

const clientSecretFromAuthoritativeIntent = (intent: Record<string, unknown> | null, prepared: PreparedPayment, expectedPaymentIntentId: string): string | null => {
  if (!intent
    || intent.id !== expectedPaymentIntentId
    || !isRecord(intent.metadata)
    || intent.metadata.order_id !== prepared.order_id
    || intent.metadata.payment_id !== prepared.payment_id
    || Number(intent.amount) !== prepared.amount_minor
    || !Number.isSafeInteger(Number(intent.amount))
    || typeof intent.currency !== 'string'
    || intent.currency.toUpperCase() !== prepared.currency_code
    || typeof intent.status !== 'string'
    || !resumablePaymentIntentStatuses.has(intent.status)
    || typeof intent.client_secret !== 'string'
    || intent.client_secret.length === 0) return null;
  return intent.client_secret;
};

const attachedPaymentIntentMatches = (value: unknown, prepared: PreparedPayment, paymentIntentId: string): boolean => isRecord(value)
  && value.payment_id === prepared.payment_id
  && value.order_id === prepared.order_id
  && value.provider_payment_intent_id === paymentIntentId;

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return fail('method_not_allowed', 'Method not allowed.', 405);
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > 4096) return fail('request_too_large', 'Request is too large.', 413);
  let body: unknown;
  try { body = await request.json(); } catch { return fail('invalid_request', 'Invalid payment request.'); }
  if (!isRecord(body) || Object.keys(body).some((key) => key !== 'orderId' && key !== 'paymentCapability') || typeof body.orderId !== 'string' || !uuidPattern.test(body.orderId)) return fail('invalid_request', 'Invalid payment request.');
  const orderId = body.orderId;
  const paymentCapability = decodePaymentCapability(body.paymentCapability);
  if (!paymentCapability) return fail('invalid_request', 'Invalid payment request.');

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseSecretKey = readDefaultSecretKey();
  const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')?.trim();
  if (!supabaseUrl || !supabaseSecretKey || !stripeSecretKey || !stripeSecretKey.startsWith('sk_test_')) return fail('payment_unavailable', 'Online payment is temporarily unavailable.', 503);

  const rateLimit = await enforceGuestRateLimit(
    request,
    'create-stripe-payment-intent',
    `payment-intent:order-capability:${orderId}:${body.paymentCapability}`,
    supabaseUrl,
    supabaseSecretKey
  );
  if (rateLimit.kind === 'unavailable') return fail('payment_unavailable', 'Online payment is temporarily unavailable.', 503);
  if (rateLimit.kind === 'limited') return fail('rate_limited', 'Too many requests. Please try again shortly.', 429, { 'Retry-After': String(rateLimit.retryAfterSeconds) });

  const client = createClient(supabaseUrl, supabaseSecretKey);
  const capabilityHash = await sha256Hex(paymentCapability);
  const prepare = async (): Promise<PreparedPayment | null> => {
    const { data, error } = await client.rpc('prepare_stripe_payment_attempt', { p_order_id: orderId, p_payment_capability_hash: capabilityHash });
    if (error) return null;
    return toPreparedPayment(Array.isArray(data) ? data[0] : data);
  };

  let prepared = await prepare();
  if (!prepared) return fail('payment_unavailable', 'This payment session is no longer available. Please place your order again.');

  const retrieveCanonicalIntent = async (attempt: PreparedPayment): Promise<string | null> => {
    if (!attempt.provider_payment_intent_id) return null;
    const intent = await stripeRequest(`payment_intents/${encodeURIComponent(attempt.provider_payment_intent_id)}`, stripeSecretKey, { method: 'GET' });
    return clientSecretFromAuthoritativeIntent(intent, attempt, attempt.provider_payment_intent_id);
  };

  let clientSecret: string | null;
  if (prepared.provider_payment_intent_id) {
    clientSecret = await retrieveCanonicalIntent(prepared);
  } else {
    const form = new URLSearchParams();
    form.set('amount', String(prepared.amount_minor));
    form.set('currency', 'gbp');
    form.append('payment_method_types[]', 'card');
    form.set('metadata[order_id]', prepared.order_id);
    form.set('metadata[payment_id]', prepared.payment_id);
    const paymentIntent = await stripeRequest('payment_intents', stripeSecretKey, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Idempotency-Key': prepared.provider_idempotency_key },
      body: form.toString()
    });
    const paymentIntentId = typeof paymentIntent?.id === 'string' ? paymentIntent.id : null;
    if (!paymentIntentId) return fail('payment_unavailable', 'Online payment is temporarily unavailable.', 503);
    clientSecret = clientSecretFromAuthoritativeIntent(paymentIntent, prepared, paymentIntentId);
    if (!clientSecret) return fail('payment_unavailable', 'Payment could not be started. Please try again.', 503);
    const { data, error } = await client.rpc('attach_stripe_payment_intent', {
      p_payment_id: prepared.payment_id,
      p_expected_provider_payment_intent_id: null,
      p_provider_payment_intent_id: paymentIntentId
    });
    const attached = Array.isArray(data) ? data[0] : data;
    if (error || !attachedPaymentIntentMatches(attached, prepared, paymentIntentId)) {
      prepared = await prepare();
      if (!prepared?.provider_payment_intent_id) return fail('payment_unavailable', 'Payment could not be resumed. Please try again.');
      clientSecret = await retrieveCanonicalIntent(prepared);
    }
  }

  if (!clientSecret) return fail('payment_unavailable', 'Payment could not be started. Please try again.', 503);
  return new Response(JSON.stringify({ ok: true, clientSecret }), { headers: { ...headers, 'Content-Type': 'application/json' } });
});
