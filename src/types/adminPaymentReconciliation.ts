import { z } from 'zod';

export const LATE_PAYMENT_RESOLUTION_CODES = ['refunded', 'customer_contacted_closed', 'other'] as const;
export type LatePaymentResolutionCode = (typeof LATE_PAYMENT_RESOLUTION_CODES)[number];

export const latePaymentResolutionSchema = z.object({
  paymentId: z.string().uuid(),
  resolutionCode: z.enum(LATE_PAYMENT_RESOLUTION_CODES),
  reference: z.string().trim().max(255).nullable(),
  note: z.string().trim().max(500).nullable()
});

export type LatePaymentResolutionInput = z.infer<typeof latePaymentResolutionSchema>;

export interface LatePaymentReconciliationItem {
  payment_id: string;
  order_id: string;
  order_number: string;
  amount_minor: number | string;
  currency_code: string;
  provider_payment_intent_id: string | null;
  provider_charge_id: string | null;
  provider_succeeded_at: string | null;
  payment_status: 'late_success_requires_reconciliation';
  reconciled: boolean;
  reconciliation_resolved_at: string | null;
  reconciliation_resolved_by: string | null;
  reconciliation_resolution_code: LatePaymentResolutionCode | null;
  reconciliation_reference: string | null;
  reconciliation_note: string | null;
  order_status: string;
  reservation_expires_at: string;
  cancellation_reason: string | null;
  cancelled_at: string | null;
}
