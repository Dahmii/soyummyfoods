import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type EndpointScope = 'guest-checkout' | 'create-stripe-payment-intent' | 'guest-order-status';

type RateLimitDecision =
  | { kind: 'allowed' }
  | { kind: 'limited'; retryAfterSeconds: number }
  | { kind: 'unavailable' };

const encoder = new TextEncoder();
const hmacPattern = /^[0-9a-f]{64}$/;

const toHex = (bytes: Uint8Array): string => Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');

const normalizeIpv4 = (value: string): string | null => {
  const parts = value.split('.');
  if (parts.length !== 4 || !parts.every((part) => /^\d{1,3}$/.test(part))) return null;
  const octets = parts.map(Number);
  if (octets.some((octet) => octet > 255)) return null;
  return octets.join('.');
};

const normalizeIpv6 = (value: string): string | null => {
  const candidate = value.startsWith('[') && value.endsWith(']') ? value.slice(1, -1) : value;
  if (!/^[0-9a-f:]+$/i.test(candidate) || !candidate.includes(':')) return null;
  const compressedParts = candidate.split('::');
  if (compressedParts.length > 2) return null;
  const parsePart = (part: string): string[] | null => {
    if (part.length === 0) return [];
    const segments = part.split(':');
    return segments.every((segment) => /^[0-9a-f]{1,4}$/i.test(segment)) ? segments : null;
  };
  const left = parsePart(compressedParts[0]);
  const right = compressedParts.length === 2 ? parsePart(compressedParts[1]) : [];
  if (!left || !right) return null;
  const segmentCount = left.length + right.length;
  if ((compressedParts.length === 1 && segmentCount !== 8) || (compressedParts.length === 2 && segmentCount >= 8)) return null;
  const segments = compressedParts.length === 2
    ? [...left, ...Array.from({ length: 8 - segmentCount }, () => '0'), ...right]
    : left;
  return segments.map((segment) => Number.parseInt(segment, 16).toString(16).padStart(4, '0')).join(':');
};

const normalizedForwardedIp = (request: Request): string | null => {
  const forwardedFor = request.headers.get('x-forwarded-for');
  if (!forwardedFor) return null;
  const firstAddress = forwardedFor.split(',', 1)[0]?.trim() ?? '';
  return normalizeIpv4(firstAddress) ?? normalizeIpv6(firstAddress);
};

const hmacSha256Hex = async (secret: string, namespace: string, value: string): Promise<string> => {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(`${namespace}\u0000${value}`));
  return toHex(new Uint8Array(signature));
};

const isRateLimitResponse = (value: unknown): value is { allowed: boolean; retry_after_seconds: number } => typeof value === 'object'
  && value !== null
  && !Array.isArray(value)
  && typeof (value as Record<string, unknown>).allowed === 'boolean'
  && typeof (value as Record<string, unknown>).retry_after_seconds === 'number';

export async function enforceGuestRateLimit(
  request: Request,
  endpoint: EndpointScope,
  attemptIdentifier: string,
  supabaseUrl: string,
  supabaseSecretKey: string
): Promise<RateLimitDecision> {
  const hmacSecret = Deno.env.get('RATE_LIMIT_HMAC_KEY')?.trim();
  if (!hmacSecret || hmacSecret.length < 32) {
    console.error('guest rate limit configuration error: RATE_LIMIT_HMAC_KEY is missing or invalid.');
    return { kind: 'unavailable' };
  }

  try {
    const attemptKey = await hmacSha256Hex(hmacSecret, `guest-rate-limit:v1:${endpoint}:attempt`, attemptIdentifier);
    const clientIp = normalizedForwardedIp(request);
    if (!clientIp) console.warn('guest rate limit warning: X-Forwarded-For is unavailable or invalid; enforcing attempt limit only.');
    const ipKey = clientIp
      ? await hmacSha256Hex(hmacSecret, `guest-rate-limit:v1:${endpoint}:ip`, clientIp)
      : null;

    if (!hmacPattern.test(attemptKey) || (ipKey !== null && !hmacPattern.test(ipKey))) return { kind: 'unavailable' };
    const client = createClient(supabaseUrl, supabaseSecretKey);
    const { data, error } = await client.rpc('consume_guest_rate_limit', {
      p_endpoint: endpoint,
      p_ip_key: ipKey,
      p_attempt_key: attemptKey
    });
    const result = Array.isArray(data) ? data[0] : data;
    if (error || !isRateLimitResponse(result) || !Number.isSafeInteger(result.retry_after_seconds) || result.retry_after_seconds < 0) {
      return { kind: 'unavailable' };
    }
    return result.allowed
      ? { kind: 'allowed' }
      : { kind: 'limited', retryAfterSeconds: Math.max(1, result.retry_after_seconds) };
  } catch {
    console.error('guest rate limit unavailable due to runtime error');
    return { kind: 'unavailable' };
  }
}
