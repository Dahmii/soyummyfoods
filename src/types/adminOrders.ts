import { z } from 'zod';

export const ADMIN_ORDER_STATUSES = ['pending_payment', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled'] as const;
export type AdminOrderStatus = (typeof ADMIN_ORDER_STATUSES)[number];

export const ADMIN_OPERATIONAL_PAYMENT_STATUSES = [
  'awaiting_payment_intent',
  'payment_intent_attached',
  'payment_failed',
  'succeeded',
  'late_success_requires_reconciliation'
] as const;
export type AdminOperationalPaymentStatus = (typeof ADMIN_OPERATIONAL_PAYMENT_STATUSES)[number];

export const ADMIN_ACTIONABLE_ORDER_STATUSES = ['confirmed', 'preparing', 'ready'] as const;
export type AdminActionableOrderStatus = (typeof ADMIN_ACTIONABLE_ORDER_STATUSES)[number];

export const adminOrderFiltersSchema = z.object({
  status: z.enum(ADMIN_ORDER_STATUSES).nullable(),
  createdDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
  search: z.string().trim().max(100).nullable(),
  pendingOnly: z.boolean()
});

export const adminOrderCursorSchema = z.object({
  createdAt: z.string().datetime({ offset: true }),
  id: z.string().uuid()
});

export const adminOrderTransitionSchema = z.object({
  orderId: z.string().uuid(),
  expectedStatus: z.enum(ADMIN_ORDER_STATUSES),
  nextStatus: z.enum(ADMIN_ORDER_STATUSES),
  reason: z.string().trim().max(500).nullable()
}).superRefine((value, context) => {
  if (value.expectedStatus === 'pending_payment' && value.nextStatus === 'cancelled' && !value.reason) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'A cancellation reason is required.' });
  }
});

export type AdminOrderFilters = z.infer<typeof adminOrderFiltersSchema>;
export type AdminOrderCursor = z.infer<typeof adminOrderCursorSchema>;
export type AdminOrderTransitionInput = z.infer<typeof adminOrderTransitionSchema>;

export interface AdminOrderListItem {
  id: string;
  order_number: string;
  status: AdminOrderStatus;
  customer_name: string;
  postcode_snapshot: string;
  delivery_zone_name_snapshot: string;
  total: number | string;
  currency_code: string;
  reservation_expires_at: string;
  created_at: string;
}

export interface AdminActionableOrder {
  id: string;
  order_number: string;
  status: AdminActionableOrderStatus;
  total: number | string;
  currency_code: string;
  created_at: string;
}

export interface AdminOrderDetail extends AdminOrderListItem {
  customer_email: string;
  customer_phone: string;
  delivery_address: string;
  subtotal: number | string;
  delivery_fee: number | string;
  discount_amount: number | string;
  tax_amount: number | string;
  customer_note: string | null;
  updated_at: string;
}

export interface AdminOrderPaymentSummary {
  order_id: string;
  payment_status: AdminOperationalPaymentStatus;
  amount_minor: number | string;
  currency_code: string;
  provider: 'stripe';
  paid_at: string | null;
  requires_manager_review: boolean;
}

export interface AdminOrderItem {
  id: string;
  order_id: string;
  product_slug_snapshot: string;
  product_name_snapshot: string;
  portion_note_snapshot: string | null;
  quantity: number;
  unit_price: number | string;
  line_subtotal: number | string;
  created_at: string;
}

export interface AdminOrderStatusHistory {
  id: string;
  order_id: string;
  previous_status: AdminOrderStatus | null;
  new_status: AdminOrderStatus;
  actor_user_id: string | null;
  actor_display_name: string;
  reason: string | null;
  created_at: string;
}

export interface AdminOrderReceiptArtifactStatus {
  financial_document_id: string;
  document_number: string;
  artifact_id: string | null;
  generated_at: string | null;
}

export interface AdminReceiptDownload {
  signedUrl: string;
  generated: boolean;
}

export interface AdminOrderPage {
  orders: AdminOrderListItem[];
  nextCursor: AdminOrderCursor | null;
}
