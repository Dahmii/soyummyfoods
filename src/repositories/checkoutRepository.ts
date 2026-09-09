import { getSupabaseClient } from '../lib/supabase';
import type { CheckoutRequest, CheckoutResponse } from '../types/order';

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
