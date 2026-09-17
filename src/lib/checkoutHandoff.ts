import type { CheckoutResponse } from '../types/order';

const ACTIVE_STORAGE_KEY = 'soyummy:active-checkout-handoff';
const CONFIRMED_STORAGE_KEY = 'soyummy:confirmed-checkout-handoff';
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const currencyPattern = /^[A-Z]{3}$/;

export interface CheckoutHandoff {
  checkoutAttemptId: string;
  orderId: string;
  orderNumber: string;
  subtotal: number;
  deliveryFee: number;
  discountAmount: number;
  taxAmount: number;
  total: number;
  currency: string;
  reservationExpiresAt: string;
  createdAt: string;
  lifecycle: 'active' | 'confirmed';
}

function sessionStorageOrNull(): Storage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

function isAmount(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function parseHandoff(value: unknown): CheckoutHandoff | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
  const handoff = value as Record<string, unknown>;
  const isValid = typeof handoff.checkoutAttemptId === 'string'
    && uuidPattern.test(handoff.checkoutAttemptId)
    && typeof handoff.orderId === 'string'
    && uuidPattern.test(handoff.orderId)
    && typeof handoff.orderNumber === 'string'
    && handoff.orderNumber.length > 0
    && handoff.orderNumber.length <= 100
    && isAmount(handoff.subtotal)
    && isAmount(handoff.deliveryFee)
    && isAmount(handoff.discountAmount)
    && isAmount(handoff.taxAmount)
    && isAmount(handoff.total)
    && typeof handoff.currency === 'string'
    && currencyPattern.test(handoff.currency)
    && typeof handoff.reservationExpiresAt === 'string'
    && Number.isFinite(Date.parse(handoff.reservationExpiresAt))
    && typeof handoff.createdAt === 'string'
    && Number.isFinite(Date.parse(handoff.createdAt))
    && (handoff.lifecycle === undefined || handoff.lifecycle === 'active' || handoff.lifecycle === 'confirmed');
  if (!isValid) return null;
  return {
    checkoutAttemptId: handoff.checkoutAttemptId as string,
    orderId: handoff.orderId as string,
    orderNumber: handoff.orderNumber as string,
    subtotal: handoff.subtotal as number,
    deliveryFee: handoff.deliveryFee as number,
    discountAmount: handoff.discountAmount as number,
    taxAmount: handoff.taxAmount as number,
    total: handoff.total as number,
    currency: handoff.currency as string,
    reservationExpiresAt: handoff.reservationExpiresAt as string,
    createdAt: handoff.createdAt as string,
    lifecycle: handoff.lifecycle === 'confirmed' ? 'confirmed' : 'active'
  };
}

function loadFrom(storageKey: string): CheckoutHandoff | null {
  const storage = sessionStorageOrNull();
  if (!storage) return null;
  try {
    const raw = storage.getItem(storageKey);
    if (!raw) return null;
    const handoff = parseHandoff(JSON.parse(raw) as unknown);
    if (handoff) return handoff;
    storage.removeItem(storageKey);
  } catch {
    try {
      storage.removeItem(storageKey);
    } catch {
      // Recovery state is optional; a storage failure must not crash the app.
    }
  }
  return null;
}

function saveTo(storageKey: string, handoff: CheckoutHandoff): boolean {
  const storage = sessionStorageOrNull();
  if (!storage) return false;
  try {
    storage.setItem(storageKey, JSON.stringify(handoff));
    return true;
  } catch {
    return false;
  }
}

/**
 * Saves non-secret, same-session checkout context. The raw payment capability
 * remains exclusively in paymentCapability.ts under its per-attempt key.
 */
export function saveCheckoutHandoff(order: CheckoutResponse, checkoutAttemptId: string): boolean {
  const storage = sessionStorageOrNull();
  if (!storage) return false;

  const handoff: CheckoutHandoff = {
    checkoutAttemptId,
    orderId: order.orderId,
    orderNumber: order.orderNumber,
    subtotal: order.subtotal,
    deliveryFee: order.deliveryFee,
    discountAmount: order.discountAmount,
    taxAmount: order.taxAmount,
    total: order.total,
    currency: order.currency,
    reservationExpiresAt: order.reservationExpiresAt,
    createdAt: new Date().toISOString(),
    lifecycle: 'active'
  };
  return saveTo(ACTIVE_STORAGE_KEY, handoff);
}

/** Returns validated same-session recovery context without minting any token. */
export function loadCheckoutHandoff(): CheckoutHandoff | null {
  return loadActiveCheckoutHandoff() ?? loadFrom(CONFIRMED_STORAGE_KEY);
}

export function loadActiveCheckoutHandoff(): CheckoutHandoff | null {
  return loadFrom(ACTIVE_STORAGE_KEY);
}

export function markCheckoutHandoffConfirmed(handoff: CheckoutHandoff): void {
  const active = loadActiveCheckoutHandoff();
  if (!active || active.checkoutAttemptId !== handoff.checkoutAttemptId || active.orderId !== handoff.orderId) return;
  const confirmedHandoff: CheckoutHandoff = { ...active, lifecycle: 'confirmed' };
  if (!saveTo(CONFIRMED_STORAGE_KEY, confirmedHandoff)) return;
  try {
    sessionStorageOrNull()?.removeItem(ACTIVE_STORAGE_KEY);
  } catch {
    // A retained active handoff is conservative: it prevents a duplicate order.
  }
}

export function clearActiveCheckoutHandoff(handoff: CheckoutHandoff): void {
  const active = loadActiveCheckoutHandoff();
  if (!active || active.checkoutAttemptId !== handoff.checkoutAttemptId || active.orderId !== handoff.orderId) return;
  try {
    sessionStorageOrNull()?.removeItem(ACTIVE_STORAGE_KEY);
  } catch {
    // Cleanup is best-effort and must not mask an authoritative terminal result.
  }
}
