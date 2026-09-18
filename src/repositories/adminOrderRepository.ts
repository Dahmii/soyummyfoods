import { getSupabaseClient } from '../lib/supabase';
import {
  ADMIN_ACTIONABLE_ORDER_STATUSES,
  adminOrderCursorSchema,
  adminOrderFiltersSchema,
  adminOrderTransitionSchema,
  type AdminOrderCursor,
  type AdminActionableOrder,
  type AdminOrderDetail,
  type AdminOrderFilters,
  type AdminOrderItem,
  type AdminOrderListItem,
  type AdminOrderPage,
  type AdminOrderReceiptArtifactStatus,
  type AdminReceiptDownload,
  type AdminOrderStatusHistory,
  type AdminOrderTransitionInput
} from '../types/adminOrders';

const PAGE_SIZE = 25;
const OPERATIONAL_QUEUE_LIMIT = 8;

function fail(error: { message: string } | null): void {
  if (error) throw new Error(error.message);
}

function nextUtcDate(date: string): string {
  const value = new Date(`${date}T00:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + 1);
  return value.toISOString();
}

function escapeOrFilter(value: string): string {
  return value.replace(/[(),]/g, '');
}

export async function listAdminOrders(filters: AdminOrderFilters, cursor: AdminOrderCursor | null): Promise<AdminOrderPage> {
  const parsedFilters = adminOrderFiltersSchema.parse(filters);
  const parsedCursor = cursor ? adminOrderCursorSchema.parse(cursor) : null;
  const client = getSupabaseClient();
  let query = client
    .from('orders')
    .select('id, order_number, status, customer_name, postcode_snapshot, delivery_zone_name_snapshot, total, currency_code, reservation_expires_at, created_at')
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(PAGE_SIZE + 1);

  const status = parsedFilters.pendingOnly ? 'pending_payment' : parsedFilters.status;
  if (status) query = query.eq('status', status);
  if (parsedFilters.createdDate) {
    query = query.gte('created_at', `${parsedFilters.createdDate}T00:00:00.000Z`).lt('created_at', nextUtcDate(parsedFilters.createdDate));
  }
  if (parsedFilters.search) {
    const value = escapeOrFilter(parsedFilters.search);
    if (value) query = query.or(`order_number.ilike.%${value}%,customer_name.ilike.%${value}%`);
  }
  if (parsedCursor) {
    query = query.or(`created_at.lt.${parsedCursor.createdAt},and(created_at.eq.${parsedCursor.createdAt},id.lt.${parsedCursor.id})`);
  }

  const { data, error } = await query;
  fail(error);
  const rows = (data ?? []) as AdminOrderListItem[];
  const hasMore = rows.length > PAGE_SIZE;
  const orders = hasMore ? rows.slice(0, PAGE_SIZE) : rows;
  const last = orders.at(-1);
  return {
    orders,
    nextCursor: hasMore && last ? { createdAt: last.created_at, id: last.id } : null
  };
}

export async function listAdminActionableOrders(): Promise<AdminActionableOrder[]> {
  const { data, error } = await getSupabaseClient()
    .from('orders')
    .select('id, order_number, status, total, currency_code, created_at')
    .in('status', ADMIN_ACTIONABLE_ORDER_STATUSES)
    .order('created_at', { ascending: true })
    .order('id', { ascending: true })
    .limit(OPERATIONAL_QUEUE_LIMIT);
  fail(error);
  return (data ?? []) as AdminActionableOrder[];
}

export async function countAdminConfirmedOrders(): Promise<number> {
  const { count, error } = await getSupabaseClient()
    .from('orders')
    .select('id', { count: 'exact', head: true })
    .eq('status', 'confirmed');
  fail(error);
  return count ?? 0;
}

export async function getAdminOrder(orderId: string): Promise<AdminOrderDetail | null> {
  const id = adminOrderCursorSchema.shape.id.parse(orderId);
  const { data, error } = await getSupabaseClient()
    .from('orders')
    .select('id, order_number, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, customer_note, reservation_expires_at, created_at, updated_at')
    .eq('id', id)
    .maybeSingle();
  fail(error);
  return data as AdminOrderDetail | null;
}

export async function listAdminOrderItems(orderId: string): Promise<AdminOrderItem[]> {
  const id = adminOrderCursorSchema.shape.id.parse(orderId);
  const { data, error } = await getSupabaseClient()
    .from('order_items')
    .select('id, order_id, product_slug_snapshot, product_name_snapshot, portion_note_snapshot, quantity, unit_price, line_subtotal, created_at')
    .eq('order_id', id)
    .order('created_at');
  fail(error);
  return (data ?? []) as AdminOrderItem[];
}

export async function listAdminOrderStatusHistory(orderId: string): Promise<AdminOrderStatusHistory[]> {
  const id = adminOrderCursorSchema.shape.id.parse(orderId);
  const { data, error } = await getSupabaseClient().rpc('get_admin_order_status_history', { p_order_id: id });
  fail(error);
  return (data ?? []) as AdminOrderStatusHistory[];
}

export async function getAdminOrderReceiptArtifactStatus(orderId: string): Promise<AdminOrderReceiptArtifactStatus | null> {
  const id = adminOrderCursorSchema.shape.id.parse(orderId);
  const { data, error } = await getSupabaseClient().rpc('get_admin_order_receipt_artifact_status', { p_order_id: id });
  fail(error);
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;
  return row as AdminOrderReceiptArtifactStatus;
}

export async function generateAdminReceiptPdf(receiptOrOrderId: string, recoveryOrder = false): Promise<AdminReceiptDownload> {
  const id = adminOrderCursorSchema.shape.id.parse(receiptOrOrderId);
  const { data, error } = await getSupabaseClient().functions.invoke('generate-receipt-pdf', { body: recoveryOrder ? { orderId: id } : { documentId: id } });
  if (error) {
    const context = (error as { context?: unknown }).context;
    if (context instanceof Response) {
      const payload: unknown = await context.json().catch(() => null);
      if (payload && typeof payload === 'object' && 'message' in payload && typeof payload.message === 'string') {
        throw new Error(payload.message);
      }
    }
    throw new Error(error.message || 'Could not generate the receipt PDF.');
  }
  if (!data || data.ok !== true || typeof data.signedUrl !== 'string') {
    const message = data && typeof data.message === 'string' ? data.message : 'Could not generate the receipt PDF.';
    throw new Error(message);
  }
  return { signedUrl: data.signedUrl, generated: data.generated === true };
}

export async function transitionAdminOrderStatus(input: AdminOrderTransitionInput): Promise<AdminOrderDetail> {
  const parsed = adminOrderTransitionSchema.parse(input);
  const { data, error } = await getSupabaseClient().rpc('transition_admin_order_status', {
    p_order_id: parsed.orderId,
    p_expected_status: parsed.expectedStatus,
    p_next_status: parsed.nextStatus,
    p_reason: parsed.reason
  });
  fail(error);
  return data as AdminOrderDetail;
}
