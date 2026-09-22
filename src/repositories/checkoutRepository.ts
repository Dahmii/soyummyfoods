import { getSupabaseClient } from '../lib/supabase';
import type { CheckoutRequest, CheckoutResponse, GuestOrderPaymentStatus, StripePaymentIntentResponse } from '../types/order';

export class CheckoutError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
  }
}

export async function createGuestOrder(request: CheckoutRequest): Promise<CheckoutResponse> {
  const { data, error } = await getSupabaseClient().functions.invoke('guest-checkout', { body: request });
  if (error) {
    const response = error.context;
    if (response instanceof Response) {
      const body = await response.json().catch(() => null) as { code?: unknown; message?: unknown } | null;
      if (typeof body?.message === 'string') throw new CheckoutError(typeof body.code === 'string' ? body.code : 'checkout_failed', body.message);
    }
    throw new Error('Checkout could not be completed. Please try again.');
  }
  if (!data?.ok) throw new Error(data?.message ?? 'Checkout could not be completed.');
  return data.order as CheckoutResponse;
}

export async function createStripePaymentIntent(orderId: string, paymentCapability: string): Promise<StripePaymentIntentResponse> {
  const { data, error } = await getSupabaseClient().functions.invoke('create-stripe-payment-intent', {
    body: { orderId, paymentCapability }
  });
  if (error) {
    const response = error.context;
    if (response instanceof Response) {
      const body = await response.json().catch(() => null) as { code?: unknown; message?: unknown } | null;
      if (typeof body?.message === 'string') throw new CheckoutError(typeof body.code === 'string' ? body.code : 'payment_unavailable', body.message);
    }
    throw new Error('Payment could not be started. Please try again.');
  }
  if (!data?.ok
    || typeof data.clientSecret !== 'string'
    || (data.stripeMode !== 'test' && data.stripeMode !== 'live')) {
    throw new Error(data?.message ?? 'Payment could not be started. Please try again.');
  }
  return { clientSecret: data.clientSecret, stripeMode: data.stripeMode };
}

export async function getGuestOrderPaymentStatus(orderId: string, paymentCapability: string): Promise<GuestOrderPaymentStatus> {
  const { data, error } = await getSupabaseClient().functions.invoke('guest-order-status', {
    body: { orderId, paymentCapability }
  });
  if (error || !data?.ok || !data.status) throw new CheckoutError('order_status_unavailable', 'Order status is unavailable.');
  return data.status as GuestOrderPaymentStatus;
}
