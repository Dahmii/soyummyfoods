import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Field, Input } from '../../components/ui/input';
import { Select } from '../../components/ui/select';
import { listAdminOrders } from '../../repositories/adminOrderRepository';
import { type AdminOrderCursor, type AdminOrderFilters, type AdminOrderListItem, ADMIN_ORDER_STATUSES } from '../../types/adminOrders';
import { formatPrice } from '../../utils/currency';

const initialFilters: AdminOrderFilters = { status: null, createdDate: null, search: null, pendingOnly: false };

function statusLabel(status: string): string {
  return status.replace(/_/g, ' ');
}

export function AdminOrdersPage() {
  const [draftFilters, setDraftFilters] = useState<AdminOrderFilters>(initialFilters);
  const [filters, setFilters] = useState<AdminOrderFilters>(initialFilters);
  const [orders, setOrders] = useState<AdminOrderListItem[]>([]);
  const [cursor, setCursor] = useState<AdminOrderCursor | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (append: boolean, pageCursor: AdminOrderCursor | null) => {
    setError(null);
    append ? setLoadingMore(true) : setLoading(true);
    try {
      const page = await listAdminOrders(filters, append ? pageCursor : null);
      setOrders((current) => append ? [...current, ...page.orders] : page.orders);
      setCursor(page.nextCursor);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load orders.');
    } finally {
      append ? setLoadingMore(false) : setLoading(false);
    }
  }, [filters]);

  useEffect(() => { void load(false, null); }, [load]);

  function applyFilters(event: React.FormEvent) {
    event.preventDefault();
    setFilters({ ...draftFilters, search: draftFilters.search?.trim() || null });
  }

  return <section className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4">
      <div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Operations</p><h1 className="mt-2 font-display text-3xl font-bold">Orders</h1><p className="mt-2 text-sm text-ink/60">Operational order records and immutable customer, delivery, and price snapshots.</p></div>
      <Button variant="outline" onClick={() => void load(false, null)} disabled={loading}>Refresh</Button>
    </div>
    <form onSubmit={applyFilters} className="grid gap-3 rounded-2xl border border-ink/10 bg-white p-4 md:grid-cols-4">
      <Field label="Search" htmlFor="order-search"><Input id="order-search" value={draftFilters.search ?? ''} onChange={(event) => setDraftFilters({ ...draftFilters, search: event.target.value })} placeholder="Order number or customer" /></Field>
      <Field label="Status" htmlFor="order-status"><Select id="order-status" value={draftFilters.status ?? ''} onChange={(event) => setDraftFilters({ ...draftFilters, status: event.target.value ? event.target.value as AdminOrderFilters['status'] : null, pendingOnly: false })} options={[{ value: '', label: 'All statuses' }, ...ADMIN_ORDER_STATUSES.map((status) => ({ value: status, label: statusLabel(status) }))]} /></Field>
      <Field label="Created date" htmlFor="order-date"><Input id="order-date" type="date" value={draftFilters.createdDate ?? ''} onChange={(event) => setDraftFilters({ ...draftFilters, createdDate: event.target.value || null })} /></Field>
      <div className="flex items-end gap-3"><label className="flex h-10 items-center gap-2 text-sm"><input type="checkbox" checked={draftFilters.pendingOnly} onChange={(event) => setDraftFilters({ ...draftFilters, pendingOnly: event.target.checked, status: event.target.checked ? 'pending_payment' : draftFilters.status })} /> Pending payment</label><Button type="submit">Apply</Button></div>
    </form>
    {error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}
    {loading ? <p>Loading orders…</p> : orders.length === 0 ? <div className="rounded-2xl border border-dashed border-ink/20 bg-white p-6 text-sm text-ink/60">No orders match the current filters.</div> : <div className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Order</th><th className="p-4">Customer</th><th className="p-4">Delivery</th><th className="p-4">Total</th><th className="p-4">Status</th><th className="p-4">Created</th><th className="p-4" /></tr></thead><tbody>{orders.map((order) => <tr key={order.id} className="border-t border-ink/10"><td className="p-4 font-semibold">{order.order_number}</td><td className="p-4">{order.customer_name}</td><td className="p-4">{order.postcode_snapshot}<span className="block text-xs text-ink/50">{order.delivery_zone_name_snapshot}</span></td><td className="p-4">{formatPrice(Number(order.total))} {order.currency_code}</td><td className="p-4"><span className="capitalize">{statusLabel(order.status)}</span>{order.status === 'pending_payment' ? <span className="block text-xs text-ink/50">Expires {new Date(order.reservation_expires_at).toLocaleString()}</span> : null}</td><td className="p-4">{new Date(order.created_at).toLocaleString()}</td><td className="p-4 text-right"><Button asChild size="sm" variant="outline"><Link to={`/admin/orders/${order.id}`}>View</Link></Button></td></tr>)}</tbody></table></div>}
    {cursor ? <div className="flex justify-center"><Button variant="outline" onClick={() => void load(true, cursor)} disabled={loadingMore}>{loadingMore ? 'Loading…' : 'Load more'}</Button></div> : null}
  </section>;
}
