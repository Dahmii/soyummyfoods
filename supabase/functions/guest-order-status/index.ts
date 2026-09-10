import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const fail = (status = 400) => new Response(JSON.stringify({ ok: false, code: 'order_status_unavailable', message: 'Order status is unavailable.' }), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const paymentCapabilityPattern = /^[A-Za-z0-9_-]{43}$/;
const orderStatuses = new Set(['pending_payment', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled']);
const paymentStatuses = new Set(['awaiting_payment_intent', 'payment_intent_attached', 'payment_failed', 'succeeded', 'late_success_requires_reconciliation']);

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
    console.error('guest-order-status configuration error: SUPABASE_SECRET_KEYS is missing.');
    return null;
  }
  try {
    const parsed: unknown = JSON.parse(rawSecretKeys);
    const key = isRecord(parsed) ? parsed.default : undefined;
    if (typeof key !== 'string' || key.trim().length === 0) {
      console.error('guest-order-status configuration error: SUPABASE_SECRET_KEYS.default is missing or invalid.');
      return null;
    }
    return key.trim();
  } catch {
    console.error('guest-order-status configuration error: SUPABASE_SECRET_KEYS is not valid JSON.');
    return null;
  }
};

const toStatus = (value: unknown, requestedOrderId: string) => {
  if (!isRecord(value)
    || value.order_id !== requestedOrderId
    || typeof value.order_number !== 'string'
    || typeof value.order_status !== 'string' || !orderStatuses.has(value.order_status)
    || typeof value.payment_status !== 'string' || !paymentStatuses.has(value.payment_status)
    || typeof value.terminal !== 'boolean') return null;
  return {
    orderId: value.order_id,
    orderNumber: value.order_number,
    orderStatus: value.order_status,
    paymentStatus: value.payment_status,
    terminal: value.terminal
  };
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return fail(405);
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > 4096) return fail(413);
  let body: unknown;
  try { body = await request.json(); } catch { return fail(); }
  if (!isRecord(body) || Object.keys(body).some((key) => key !== 'orderId' && key !== 'paymentCapability') || typeof body.orderId !== 'string' || !uuidPattern.test(body.orderId)) return fail();
  const paymentCapability = decodePaymentCapability(body.paymentCapability);
  if (!paymentCapability) return fail();

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const secretKey = readDefaultSecretKey();
  if (!supabaseUrl || !secretKey) return fail(503);
  const client = createClient(supabaseUrl, secretKey);
  const paymentCapabilityHash = await sha256Hex(paymentCapability);
  const { data, error } = await client.rpc('get_guest_order_payment_status', {
    p_order_id: body.orderId,
    p_payment_capability_hash: paymentCapabilityHash
  });
  if (error) return fail(503);
  const status = toStatus(Array.isArray(data) ? data[0] : data, body.orderId);
  if (!status) return fail();
  return new Response(JSON.stringify({ ok: true, status }), { headers: { ...headers, 'Content-Type': 'application/json' } });
});
