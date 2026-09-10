const CAPABILITY_BYTE_LENGTH = 32;
const STORAGE_KEY_PREFIX = 'soyummy:payment-capability:';

// A 32-byte value encodes to exactly 43 unpadded base64url characters.
export const paymentCapabilityPattern = /^[A-Za-z0-9_-]{43}$/;

function storageKey(checkoutAttemptId: string): string {
  return `${STORAGE_KEY_PREFIX}${checkoutAttemptId}`;
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function generatePaymentCapability(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(CAPABILITY_BYTE_LENGTH));
  return encodeBase64Url(bytes);
}

function getSessionStorage(): Storage {
  try {
    return window.sessionStorage;
  } catch {
    throw new Error('Unable to securely prepare this checkout. Please enable session storage and try again.');
  }
}

/**
 * Returns the stable bearer capability for one idempotent checkout attempt.
 * Only the raw capability is stored, keyed by the non-PII attempt UUID.
 */
export function getOrCreatePaymentCapability(checkoutAttemptId: string): string {
  const storage = getSessionStorage();
  const key = storageKey(checkoutAttemptId);
  const existing = storage.getItem(key);
  if (existing && paymentCapabilityPattern.test(existing)) return existing;

  if (existing) storage.removeItem(key);
  const capability = generatePaymentCapability();
  try {
    storage.setItem(key, capability);
  } catch {
    throw new Error('Unable to securely prepare this checkout. Please enable session storage and try again.');
  }
  return capability;
}

/** Returns an existing capability without ever minting one for an existing order. */
export function getPaymentCapability(checkoutAttemptId: string): string | null {
  const capability = getSessionStorage().getItem(storageKey(checkoutAttemptId));
  return capability && paymentCapabilityPattern.test(capability) ? capability : null;
}

/** Removes the raw capability after the associated checkout/payment lifecycle is finished. */
export function clearPaymentCapability(checkoutAttemptId: string): void {
  try {
    getSessionStorage().removeItem(storageKey(checkoutAttemptId));
  } catch {
    // Cleanup is best-effort and must not mask the terminal checkout result.
  }
}
