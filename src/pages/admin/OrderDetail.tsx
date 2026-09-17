import React, { useCallback, useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Field, Textarea } from '../../components/ui/input';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { generateAdminReceiptPdf, getAdminOrder, getAdminOrderReceiptArtifactStatus, listAdminOrderItems, listAdminOrderStatusHistory, transitionAdminOrderStatus } from '../../repositories/adminOrderRepository';
import type { AdminOrderDetail, AdminOrderItem, AdminOrderReceiptArtifactStatus, AdminOrderStatus, AdminOrderStatusHistory } from '../../types/adminOrders';
import { formatPrice } from '../../utils/currency';

function statusLabel(status: string | null): string {
  return status ? status.replace(/_/g, ' ') : 'Created';
}

function nextAction(status: AdminOrderStatus, canCancel: boolean): { status: AdminOrderStatus; label: string } | null {
  if (status === 'pending_payment' && canCancel) return { status: 'cancelled', label: 'Cancel order' };
  if (status === 'confirmed') return { status: 'preparing', label: 'Begin preparing' };
  if (status === 'preparing') return { status: 'ready', label: 'Mark ready' };
  if (status === 'ready') return { status: 'completed', label: 'Mark completed' };
  return null;
}

export function AdminOrderDetailPage() {
  const { orderId } = useParams();
  const { roles } = useAdminAuth();
  const canCancel = roles.some((role) => role === 'manager' || role === 'owner');
  const canAccessReceipts = canCancel;
  const [order, setOrder] = useState<AdminOrderDetail | null>(null);
  const [items, setItems] = useState<AdminOrderItem[]>([]);
  const [history, setHistory] = useState<AdminOrderStatusHistory[]>([]);
  const [receipt, setReceipt] = useState<AdminOrderReceiptArtifactStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [generatingReceipt, setGeneratingReceipt] = useState(false);
  const [showCancellation, setShowCancellation] = useState(false);
  const [cancellationReason, setCancellationReason] = useState('');
  const [confirmedCancellation, setConfirmedCancellation] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!orderId) return;
    setError(null);
    const [nextOrder, nextItems, nextHistory, nextReceipt] = await Promise.all([
      getAdminOrder(orderId), listAdminOrderItems(orderId), listAdminOrderStatusHistory(orderId),
      canAccessReceipts ? getAdminOrderReceiptArtifactStatus(orderId) : Promise.resolve(null)
    ]);
    setOrder(nextOrder); setItems(nextItems); setHistory(nextHistory); setReceipt(nextReceipt); setLoading(false);
  }, [canAccessReceipts, orderId]);

  useEffect(() => { void load().catch((cause) => { setError(cause instanceof Error ? cause.message : 'Could not load this order.'); setLoading(false); }); }, [load]);

  async function transition(nextStatus: AdminOrderStatus) {
    if (!order) return;
    const reason = nextStatus === 'cancelled' ? cancellationReason.trim() || null : null;
    if (nextStatus === 'cancelled' && (!reason || !confirmedCancellation)) {
      setError(!reason ? 'A cancellation reason is required.' : 'Confirm cancellation before continuing.');
      return;
    }
    setSaving(true); setError(null);
    try {
      await transitionAdminOrderStatus({ orderId: order.id, expectedStatus: order.status, nextStatus, reason });
      setShowCancellation(false); setCancellationReason(''); setConfirmedCancellation(false);
      await load();
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : 'Could not update the order status.';
      setError(message);
      if (message.includes('Order status has changed')) void load();
    } finally {
      setSaving(false);
    }
  }

  async function viewReceipt() {
    if (!order) return;
    setGeneratingReceipt(true); setError(null);
    try {
      const result = await generateAdminReceiptPdf(receipt?.financial_document_id ?? order.id, !receipt);
      window.open(result.signedUrl, '_blank', 'noopener,noreferrer');
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not generate the receipt PDF.');
    } finally {
      setGeneratingReceipt(false);
    }
  }

  if (loading) return <p>Loading order…</p>;
  if (!order) return <section className="space-y-4"><p role="alert">Order not found.</p><Button asChild variant="ghost"><Link to="/admin/orders">Back to orders</Link></Button></section>;
  const action = nextAction(order.status, canCancel);
  return <section className="space-y-7">
    <div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Order</p><h1 className="mt-2 font-display text-3xl font-bold">{order.order_number}</h1><p className="mt-2 text-sm text-ink/60">Created {new Date(order.created_at).toLocaleString()} · Status: <span className="capitalize">{statusLabel(order.status)}</span></p>{order.status === 'pending_payment' ? <p className="mt-2 text-sm text-amber-700">Awaiting payment. Reservation expires {new Date(order.reservation_expires_at).toLocaleString()}.</p> : null}</div><Button asChild variant="outline"><Link to="/admin/orders">Back to orders</Link></Button></div>
    {error ? <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p> : null}
    <div className="grid gap-5 lg:grid-cols-2"><section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Customer</h2><dl className="mt-4 space-y-2 text-sm"><div><dt className="text-ink/50">Name</dt><dd>{order.customer_name}</dd></div><div><dt className="text-ink/50">Email</dt><dd>{order.customer_email}</dd></div><div><dt className="text-ink/50">Phone</dt><dd>{order.customer_phone}</dd></div></dl></section><section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Delivery</h2><dl className="mt-4 space-y-2 text-sm"><div><dt className="text-ink/50">Address</dt><dd className="whitespace-pre-wrap">{order.delivery_address}</dd></div><div><dt className="text-ink/50">Postcode</dt><dd>{order.postcode_snapshot}</dd></div><div><dt className="text-ink/50">Zone</dt><dd>{order.delivery_zone_name_snapshot}</dd></div></dl></section></div>
    <section className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><h2 className="border-b border-ink/10 p-5 font-display text-xl font-bold">Order items</h2><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Item</th><th className="p-4">Quantity</th><th className="p-4">Unit price</th><th className="p-4">Line total</th></tr></thead><tbody>{items.map((item) => <tr key={item.id} className="border-t border-ink/10"><td className="p-4"><strong>{item.product_name_snapshot}</strong><span className="block text-xs text-ink/50">{item.product_slug_snapshot}{item.portion_note_snapshot ? ` · ${item.portion_note_snapshot}` : ''}</span></td><td className="p-4">{item.quantity}</td><td className="p-4">{formatPrice(Number(item.unit_price))}</td><td className="p-4">{formatPrice(Number(item.line_subtotal))}</td></tr>)}</tbody></table></section>
    <div className="grid gap-5 lg:grid-cols-2"><section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Totals</h2><dl className="mt-4 space-y-2 text-sm"><div className="flex justify-between"><dt>Subtotal</dt><dd>{formatPrice(Number(order.subtotal))}</dd></div><div className="flex justify-between"><dt>Delivery</dt><dd>{formatPrice(Number(order.delivery_fee))}</dd></div><div className="flex justify-between"><dt>Discount</dt><dd>{formatPrice(Number(order.discount_amount))}</dd></div><div className="flex justify-between"><dt>Tax</dt><dd>{formatPrice(Number(order.tax_amount))}</dd></div><div className="flex justify-between border-t border-ink/10 pt-2 font-bold"><dt>Total</dt><dd>{formatPrice(Number(order.total))} {order.currency_code}</dd></div></dl></section><section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Notes</h2><p className="mt-4 whitespace-pre-wrap text-sm text-ink/70">{order.customer_note ?? 'No customer note.'}</p></section></div>
    {canAccessReceipts ? <section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Receipt</h2><div className="mt-3 flex flex-wrap items-center gap-3">{receipt ? <p className="text-sm text-ink/60">{receipt.document_number}</p> : <p className="text-sm text-ink/60">Receipt will be prepared from this verified payment.</p>}<Button onClick={() => void viewReceipt()} disabled={generatingReceipt}>{generatingReceipt ? 'Preparing receipt…' : 'Print receipt'}</Button>{receipt?.artifact_id ? <Button variant="outline" onClick={() => void viewReceipt()} disabled={generatingReceipt}>View PDF</Button> : null}</div></section> : null}
    <section className="rounded-2xl border border-ink/10 bg-white p-5"><h2 className="font-display text-xl font-bold">Status actions</h2>{order.status === 'pending_payment' && !canCancel ? <p className="mt-3 text-sm text-ink/60">Awaiting payment. Staff cannot cancel pending orders.</p> : order.status === 'pending_payment' ? !showCancellation ? <div className="mt-3"><Button variant="destructive" onClick={() => setShowCancellation(true)} disabled={saving}>Cancel order</Button></div> : <div className="mt-4 space-y-3"><Field label="Cancellation reason" htmlFor="cancellation-reason"><Textarea id="cancellation-reason" value={cancellationReason} onChange={(event) => setCancellationReason(event.target.value)} maxLength={500} disabled={saving} /></Field><label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={confirmedCancellation} onChange={(event) => setConfirmedCancellation(event.target.checked)} disabled={saving} /> I confirm this pending order should be cancelled and its reservation released.</label><div className="flex gap-3"><Button variant="destructive" onClick={() => void transition('cancelled')} disabled={saving}>Confirm cancellation</Button><Button variant="outline" onClick={() => setShowCancellation(false)} disabled={saving}>Keep order</Button></div></div> : action ? <div className="mt-3"><Button onClick={() => void transition(action.status)} disabled={saving}>{saving ? 'Saving…' : action.label}</Button></div> : <p className="mt-3 text-sm text-ink/60">No operational action is available for this status. Payment confirmation is handled in Phase 7.</p>}</section>
    <section className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><h2 className="border-b border-ink/10 p-5 font-display text-xl font-bold">Status history</h2><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">When</th><th className="p-4">Transition</th><th className="p-4">Changed by</th><th className="p-4">Reason</th></tr></thead><tbody>{history.map((entry) => <tr key={entry.id} className="border-t border-ink/10"><td className="p-4">{new Date(entry.created_at).toLocaleString()}</td><td className="p-4"><span className="capitalize">{statusLabel(entry.previous_status)}</span> → <span className="capitalize">{statusLabel(entry.new_status)}</span></td><td className="p-4">{entry.actor_display_name}</td><td className="p-4">{entry.reason ?? '—'}</td></tr>)}</tbody></table>{history.length === 0 ? <p className="p-4 text-sm text-ink/60">No status history is available.</p> : null}</section>
  </section>;
}
