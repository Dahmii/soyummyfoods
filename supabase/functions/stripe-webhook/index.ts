import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'npm:stripe@22.4.0';

const headers = { 'Content-Type': 'application/json' };
const respond = (status: number) => new Response(JSON.stringify({ received: status >= 200 && status < 300 }), { status, headers });
const providerIdentifierPattern = /^[A-Za-z0-9_]{1,255}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const failureCodePattern = /^[A-Za-z0-9_]{1,100}$/;

// Webhook verification is local cryptography; this placeholder is never used
// for a Stripe API request and prevents this function from requiring an API key.
const stripe = new Stripe('not_used_for_webhook_verification', {
  httpClient: Stripe.createFetchHttpClient()
});
const cryptoProvider = Stripe.createSubtleCryptoProvider();

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);

const sha256Hex = async (body: string): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
};

const readDefaultSecretKey = (): string | null => {
  const rawSecretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (!rawSecretKeys) {
    console.error('stripe-webhook configuration error: SUPABASE_SECRET_KEYS is missing.');
    return null;
  }
  try {
    const parsed: unknown = JSON.parse(rawSecretKeys);
    const key = isRecord(parsed) ? parsed.default : undefined;
    if (typeof key !== 'string' || key.trim().length === 0) {
      console.error('stripe-webhook configuration error: SUPABASE_SECRET_KEYS.default is missing or invalid.');
      return null;
    }
    return key.trim();
  } catch {
    console.error('stripe-webhook configuration error: SUPABASE_SECRET_KEYS is not valid JSON.');
    return null;
  }
};

const toProviderCreatedAt = (value: unknown): string | null => {
  if (!Number.isInteger(value) || (value as number) <= 0) return null;
  const date = new Date((value as number) * 1000);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

type VerifiedPaymentIntent = {
  eventId: string;
  paymentIntentId: string;
  paymentId: string;
  orderId: string;
  amountMinor: number;
  currency: string;
  chargeId: string | null;
  providerCreatedAt: string;
  failureCode: string;
};

const verifiedPaymentIntent = (event: Stripe.Event): VerifiedPaymentIntent | null => {
  const paymentIntent = event.data.object as unknown;
  if (!isRecord(paymentIntent) || !isRecord(paymentIntent.metadata)) return null;
  const eventId = event.id;
  const paymentIntentId = paymentIntent.id;
  const paymentId = paymentIntent.metadata.payment_id;
  const orderId = paymentIntent.metadata.order_id;
  const amountMinor = paymentIntent.amount;
  const currency = paymentIntent.currency;
  const providerCreatedAt = toProviderCreatedAt(event.created);
  if (typeof eventId !== 'string' || !providerIdentifierPattern.test(eventId)
    || typeof paymentIntentId !== 'string' || !providerIdentifierPattern.test(paymentIntentId)
    || typeof paymentId !== 'string' || !uuidPattern.test(paymentId)
    || typeof orderId !== 'string' || !uuidPattern.test(orderId)
    || !Number.isSafeInteger(amountMinor) || amountMinor <= 0
    || typeof currency !== 'string' || !/^[a-z]{3}$/i.test(currency)
    || !providerCreatedAt) return null;
  const chargeId = typeof paymentIntent.latest_charge === 'string' && providerIdentifierPattern.test(paymentIntent.latest_charge)
    ? paymentIntent.latest_charge
    : null;
  const rawFailureCode = isRecord(paymentIntent.last_payment_error) ? paymentIntent.last_payment_error.code : null;
  const failureCode = typeof rawFailureCode === 'string' && failureCodePattern.test(rawFailureCode) ? rawFailureCode : 'payment_failed';
  return { eventId, paymentIntentId, paymentId, orderId, amountMinor, currency: currency.toUpperCase(), chargeId, providerCreatedAt, failureCode };
};

Deno.serve(async (request) => {
  if (request.method !== 'POST') return respond(405);
  const signature = request.headers.get('stripe-signature');
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SIGNING_SECRET')?.trim();
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseSecretKey = readDefaultSecretKey();
  if (!signature) return respond(400);
  if (!webhookSecret || !supabaseUrl || !supabaseSecretKey) return respond(503);

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return respond(400);
  }

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(rawBody, signature, webhookSecret, undefined, cryptoProvider);
  } catch {
    return respond(400);
  }

  if (event.type !== 'payment_intent.succeeded' && event.type !== 'payment_intent.payment_failed') return respond(200);
  const paymentIntent = verifiedPaymentIntent(event);
  if (!paymentIntent) return respond(400);
  const payloadSha256 = await sha256Hex(rawBody);
  const client = createClient(supabaseUrl, supabaseSecretKey);

  if (event.type === 'payment_intent.succeeded') {
    const { data, error } = await client.rpc('process_verified_stripe_payment_success', {
      p_provider_event_id: paymentIntent.eventId,
      p_provider_payment_intent_id: paymentIntent.paymentIntentId,
      p_provider_charge_id: paymentIntent.chargeId,
      p_payment_id: paymentIntent.paymentId,
      p_order_id: paymentIntent.orderId,
      p_verified_amount_minor: paymentIntent.amountMinor,
      p_verified_currency: paymentIntent.currency,
      p_provider_created_at: paymentIntent.providerCreatedAt,
      p_payload_sha256: payloadSha256
    });
    if (error) return respond(500);
    const outcome = Array.isArray(data) ? data[0]?.outcome : data?.outcome;
    return ['processed', 'duplicate', 'late_success_requires_reconciliation', 'rejected'].includes(outcome) ? respond(200) : respond(500);
  }

  const { data, error } = await client.rpc('record_verified_stripe_payment_failure', {
    p_provider_event_id: paymentIntent.eventId,
    p_provider_payment_intent_id: paymentIntent.paymentIntentId,
    p_payment_id: paymentIntent.paymentId,
    p_order_id: paymentIntent.orderId,
    p_provider_created_at: paymentIntent.providerCreatedAt,
    p_failure_code: paymentIntent.failureCode,
    p_payload_sha256: payloadSha256
  });
  if (error) return respond(500);
  return ['payment_failed', 'duplicate', 'rejected'].includes(data) ? respond(200) : respond(500);
});
