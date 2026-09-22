import { z } from 'zod';
import { paymentCapabilityPattern } from '../lib/paymentCapability';

export const checkoutLineSchema = z.object({ productId: z.string().uuid(), quantity: z.number().int().min(1).max(99) });
export const checkoutRequestSchema = z.object({
  lines: z.array(checkoutLineSchema).min(1).max(20),
  customerName: z.string().trim().min(2).max(100), email: z.string().trim().email().max(254),
  phone: z.string().trim().min(7).max(32), deliveryAddress: z.string().trim().min(6).max(500),
  postcode: z.string().trim().min(2).max(16), customerNote: z.string().trim().max(500).nullable(), idempotencyKey: z.string().uuid(),
  paymentCapability: z.string().regex(paymentCapabilityPattern, 'Invalid payment session')
});
export type CheckoutRequest = z.infer<typeof checkoutRequestSchema>;
export interface CheckoutResponse { orderId: string; orderNumber: string; subtotal: number; deliveryFee: number; discountAmount: number; taxAmount: number; total: number; currency: string; status: 'pending_payment'; reservationExpiresAt: string; }
export interface StripePaymentIntentResponse { clientSecret: string; stripeMode: 'test' | 'live'; }
export interface GuestOrderPaymentStatus {
  orderId: string;
  orderNumber: string;
  orderStatus: 'pending_payment' | 'confirmed' | 'preparing' | 'ready' | 'completed' | 'cancelled';
  paymentStatus: 'awaiting_payment_intent' | 'payment_intent_attached' | 'payment_failed' | 'succeeded' | 'late_success_requires_reconciliation';
  terminal: boolean;
  subtotal: number;
  deliveryFee: number;
  discountAmount: number;
  taxAmount: number;
  total: number;
  currency: string;
  reservationExpiresAt: string;
}
