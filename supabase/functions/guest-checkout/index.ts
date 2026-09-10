import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const fail = (code: string, message: string, status = 400) => new Response(JSON.stringify({ ok: false, code, message }), { status, headers: { ...headers, 'Content-Type': 'application/json' } });
const isText = (value: unknown, minimum: number, maximum: number) => typeof value === 'string' && value.trim().length >= minimum && value.trim().length <= maximum;
const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const paymentCapabilityPattern = /^[A-Za-z0-9_-]{43}$/;

const decodePaymentCapability = (value: unknown): Uint8Array | null => {
  if (typeof value !== 'string' || !paymentCapabilityPattern.test(value)) return null;

  try {
    const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '=';
    const decoded = atob(base64);
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
    console.error('guest-checkout configuration error: SUPABASE_SECRET_KEYS is missing.');
    return null;
  }

  try {
    const parsedSecretKeys: unknown = JSON.parse(rawSecretKeys);
    const defaultSecretKey = isRecord(parsedSecretKeys) ? parsedSecretKeys.default : undefined;
    if (typeof defaultSecretKey !== 'string' || defaultSecretKey.trim().length === 0) {
      console.error('guest-checkout configuration error: SUPABASE_SECRET_KEYS.default is missing or invalid.');
      return null;
    }

    return defaultSecretKey.trim();
  } catch {
    console.error('guest-checkout configuration error: SUPABASE_SECRET_KEYS is not valid JSON.');
    return null;
  }
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return fail('method_not_allowed', 'Method not allowed.', 405);
  const length = Number(request.headers.get('content-length') ?? 0); if (length > 16_384) return fail('request_too_large', 'Request is too large.', 413);
  let body: unknown; try { body = await request.json(); } catch { return fail('invalid_request', 'Invalid checkout request.'); }
  if (!isRecord(body)) return fail('invalid_request', 'Invalid checkout request.');
  const paymentCapability = decodePaymentCapability(body.paymentCapability);
  if (!Array.isArray(body.lines) || body.lines.length < 1 || body.lines.length > 20 || !body.lines.every(isRecord)) return fail('invalid_cart', 'Your basket is invalid.');
  if (!uuidPattern.test(String(body.idempotencyKey))
    || paymentCapability === null
    || !isText(body.customerName, 2, 100) || !isText(body.email, 3, 254)
    || !isText(body.phone, 7, 32) || !isText(body.deliveryAddress, 6, 500)
    || !isText(body.postcode, 2, 16)
    || (body.customerNote !== null && body.customerNote !== undefined && !isText(body.customerNote, 0, 500))
    || !(body.lines as unknown[]).every((line) => {
      const value = line as Record<string, unknown>;
      return uuidPattern.test(String(value.productId)) && Number.isInteger(value.quantity) && Number(value.quantity) >= 1 && Number(value.quantity) <= 99;
    })) return fail('invalid_request', 'Invalid checkout request.');
  // PUBLIC PRODUCTION BLOCKER: configure durable distributed rate limiting or a
  // WAF rule in front of this public stock-reserving endpoint before production.
  // This stateless function intentionally has no pretend in-memory limiter.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const secretKey = readDefaultSecretKey();
  if (!supabaseUrl || !secretKey) return fail('service_unavailable', 'Checkout is temporarily unavailable.', 503);
  const client = createClient(supabaseUrl, secretKey);
  const paymentCapabilityHash = await sha256Hex(paymentCapability);
  const payload = { idempotency_key: body.idempotencyKey, payment_capability_hash: paymentCapabilityHash, lines: (body.lines as unknown[]).map((line) => ({ product_id: (line as Record<string, unknown>).productId, quantity: (line as Record<string, unknown>).quantity })), customer_name: body.customerName, customer_email: body.email, customer_phone: body.phone, delivery_address: body.deliveryAddress, postcode: body.postcode, customer_note: body.customerNote };
  const { data, error } = await client.rpc('create_guest_order', { p_payload: payload });
  if (error) { const codes: Record<string, string> = { unsupported_delivery_area: 'We do not currently deliver to that postcode.', minimum_order_not_met: 'This delivery zone has a minimum order value.', insufficient_stock: 'One or more items are no longer available in that quantity.', product_unavailable: 'One or more items are no longer available.', tax_configuration_required: 'Checkout is temporarily unavailable.', expired_idempotency_key: 'Your previous checkout attempt expired. Please try again.' }; const code = Object.prototype.hasOwnProperty.call(codes, error.message) ? error.message : 'checkout_failed'; return fail(code, codes[code] ?? 'Checkout could not be completed.'); }
  const order = Array.isArray(data) ? data[0] : data;
  return new Response(JSON.stringify({ ok: true, order: { orderId: order.order_id, orderNumber: order.order_number, subtotal: Number(order.subtotal), deliveryFee: Number(order.delivery_fee), discountAmount: Number(order.discount_amount), taxAmount: Number(order.tax_amount), total: Number(order.total), currency: order.currency_code, status: order.status, reservationExpiresAt: order.reservation_expires_at } }), { headers: { ...headers, 'Content-Type': 'application/json' } });
});
