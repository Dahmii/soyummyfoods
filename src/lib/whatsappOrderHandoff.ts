import type { CartLine } from '../hooks/useCartStore';
import type { CheckoutResponse } from '../types/order';

const STORAGE_KEY = 'soyummy:whatsapp-order-handoff';
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const currencyPattern = /^[A-Z]{3}$/;

export interface WhatsAppOrderHandoff {
  checkoutAttemptId: string;
  orderId: string;
  orderNumber: string;
  items: Array<{ name: string; quantity: number }>;
  financial: {
    subtotal: number;
    deliveryFee: number;
    discountAmount: number;
    taxAmount: number;
    total: number;
    currency: string;
  };
  createdAt: string;
}

export interface WhatsAppOrderHandoffIdentity {
  checkoutAttemptId: string;
  orderId: string;
  orderNumber: string;
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

function isIdentity(value: unknown): value is WhatsAppOrderHandoffIdentity {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const identity = value as Record<string, unknown>;
  return typeof identity.checkoutAttemptId === 'string'
    && uuidPattern.test(identity.checkoutAttemptId)
    && typeof identity.orderId === 'string'
    && uuidPattern.test(identity.orderId)
    && typeof identity.orderNumber === 'string'
    && identity.orderNumber.length > 0
    && identity.orderNumber.length <= 100;
}

function parseHandoff(value: unknown): WhatsAppOrderHandoff | null {
  if (!isIdentity(value)) return null;
  const handoff = value as Record<string, unknown>;
  if (!Array.isArray(handoff.items) || handoff.items.length < 1 || handoff.items.length > 20
    || !handoff.items.every((item) => typeof item === 'object' && item !== null && !Array.isArray(item)
      && typeof (item as Record<string, unknown>).name === 'string'
      && (item as Record<string, unknown>).name.trim().length > 0
      && (item as Record<string, unknown>).name.length <= 200
      && Number.isInteger((item as Record<string, unknown>).quantity)
      && Number((item as Record<string, unknown>).quantity) >= 1
      && Number((item as Record<string, unknown>).quantity) <= 99)) return null;
  if (typeof handoff.financial !== 'object' || handoff.financial === null || Array.isArray(handoff.financial)) return null;
  const financial = handoff.financial as Record<string, unknown>;
  if (!isAmount(financial.subtotal) || !isAmount(financial.deliveryFee) || !isAmount(financial.discountAmount)
    || !isAmount(financial.taxAmount) || !isAmount(financial.total)
    || typeof financial.currency !== 'string' || !currencyPattern.test(financial.currency)
    || typeof handoff.createdAt !== 'string' || !Number.isFinite(Date.parse(handoff.createdAt))) return null;

  return {
    checkoutAttemptId: handoff.checkoutAttemptId,
    orderId: handoff.orderId,
    orderNumber: handoff.orderNumber,
    items: handoff.items.map((item) => ({ name: (item as { name: string }).name, quantity: (item as { quantity: number }).quantity })),
    financial: {
      subtotal: financial.subtotal,
      deliveryFee: financial.deliveryFee,
      discountAmount: financial.discountAmount,
      taxAmount: financial.taxAmount,
      total: financial.total,
      currency: financial.currency
    },
    createdAt: handoff.createdAt
  };
}

function matches(handoff: WhatsAppOrderHandoff, identity: WhatsAppOrderHandoffIdentity): boolean {
  return handoff.checkoutAttemptId === identity.checkoutAttemptId
    && handoff.orderId === identity.orderId
    && handoff.orderNumber === identity.orderNumber;
}

function remove(): void {
  try {
    sessionStorageOrNull()?.removeItem(STORAGE_KEY);
  } catch {
    // This optional operational handoff must never affect checkout recovery.
  }
}

// TEMPORARY MANUAL HANDOFF: intended to be replaced by server-side WhatsApp Business notification.
export function saveWhatsAppOrderHandoff(order: CheckoutResponse, checkoutAttemptId: string, lines: CartLine[]): boolean {
  const storage = sessionStorageOrNull();
  const items = lines.map((line) => ({ name: line.name.trim(), quantity: line.quantity }));
  if (!storage || !uuidPattern.test(checkoutAttemptId) || !uuidPattern.test(order.orderId)
    || !order.orderNumber || !items.length || items.some((item) => !item.name || item.name.length > 200 || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 99)) return false;

  const handoff: WhatsAppOrderHandoff = {
    checkoutAttemptId,
    orderId: order.orderId,
    orderNumber: order.orderNumber,
    items,
    financial: {
      subtotal: order.subtotal,
      deliveryFee: order.deliveryFee,
      discountAmount: order.discountAmount,
      taxAmount: order.taxAmount,
      total: order.total,
      currency: order.currency
    },
    createdAt: new Date().toISOString()
  };
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify(handoff));
    return true;
  } catch {
    return false;
  }
}

export function loadWhatsAppOrderHandoff(identity: WhatsAppOrderHandoffIdentity): WhatsAppOrderHandoff | null {
  const storage = sessionStorageOrNull();
  if (!storage || !isIdentity(identity)) return null;
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const handoff = parseHandoff(JSON.parse(raw) as unknown);
    if (handoff && matches(handoff, identity)) return handoff;
  } catch {
    // Invalid session data is removed below and never used.
  }
  remove();
  return null;
}

export function clearWhatsAppOrderHandoff(identity?: WhatsAppOrderHandoffIdentity): void {
  if (!identity) {
    remove();
    return;
  }
  const storage = sessionStorageOrNull();
  if (!storage) return;
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return;
    const handoff = parseHandoff(JSON.parse(raw) as unknown);
    if (!handoff || matches(handoff, identity)) remove();
  } catch {
    remove();
  }
}
