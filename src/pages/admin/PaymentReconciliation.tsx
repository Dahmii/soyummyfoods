import React, { useCallback, useEffect, useState } from 'react';
import { Button } from '../../components/ui/button';
import { Field, Input, Textarea } from '../../components/ui/input';
import { Select } from '../../components/ui/select';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { listLatePaymentReconciliations, resolveLatePaymentReconciliation } from '../../repositories/adminPaymentReconciliationRepository';
import { LATE_PAYMENT_RESOLUTION_CODES, type LatePaymentReconciliationItem, type LatePaymentResolutionCode } from '../../types/adminPaymentReconciliation';

function formatAmount(amountMinor: number | string, currency: string): string {
  return new Intl.NumberFormat('en-GB', { style: 'currency', currency }).format(Number(amountMinor) / 100);
}

function resolutionLabel(code: LatePaymentResolutionCode): string {
  if (code === 'customer_contacted_closed') return 'Customer contacted — matter agreed/closed';
  return code.replace(/_/g, ' ');
}

export function AdminPaymentReconciliationPage() {
  const { roles } = useAdminAuth();
  const permitted = roles.some((role) => role === 'owner' || role === 'manager');
  const [items, setItems] = useState<LatePaymentReconciliationItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [savingPaymentId, setSavingPaymentId] = useState<string | null>(null);
  const [resolutionCode, setResolutionCode] = useState<LatePaymentResolutionCode>('refunded');
  const [reference, setReference] = useState('');
  const [note, setNote] = useState('');
  const [confirmingPaymentId, setConfirmingPaymentId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!permitted) return;
    setError(null);
    try {
      setItems(await listLatePaymentReconciliations());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load late-payment reconciliation items.');
    } finally {
      setLoading(false);
    }
  }, [permitted]);

  useEffect(() => { void load(); }, [load]);

  async function resolve(item: LatePaymentReconciliationItem) {
    if (confirmingPaymentId !== item.payment_id) {
      setConfirmingPaymentId(item.payment_id);
      return;
    }
    setSavingPaymentId(item.payment_id);
    setError(null);
    try {
      await resolveLatePaymentReconciliation({
        paymentId: item.payment_id,
        resolutionCode,
        reference: reference.trim() || null,
        note: note.trim() || null
      });
      setConfirmingPaymentId(null);
      setReference('');
      setNote('');
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not record the reconciliation.');
    } finally {
      setSavingPaymentId(null);
    }
  }

  if (!permitted) return <section><h1 className="font-display text-3xl font-bold">Payment reconciliation</h1><p className="mt-3 text-sm text-red-700">Manager or owner access is required.</p></section>;

  return <section className="space-y-6">
    <div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Payments</p><h1 className="mt-2 font-display text-3xl font-bold">Late-payment reconciliation</h1><p className="mt-2 text-sm text-ink/60">These verified Stripe payments arrived after the order was cancelled. Recording a resolution does not call Stripe, change the order, or alter inventory.</p></div>
    {error ? <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p> : null}
    {loading ? <p>Loading reconciliation items…</p> : items.length === 0 ? <div className="rounded-2xl border border-dashed border-ink/20 bg-white p-6 text-sm text-ink/60">No late payments require reconciliation.</div> : <div className="space-y-5">{items.map((item) => <article key={item.payment_id} className="rounded-2xl border border-amber-300 bg-white p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="font-display text-xl font-bold">{item.order_number}</h2><p className="mt-1 text-sm text-ink/60">{formatAmount(item.amount_minor, item.currency_code)} · Paid {item.provider_succeeded_at ? new Date(item.provider_succeeded_at).toLocaleString() : 'time unavailable'}</p></div><span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900">Requires reconciliation</span></div><dl className="mt-4 grid gap-3 text-sm md:grid-cols-2"><div><dt className="text-ink/50">Order context</dt><dd className="capitalize">{item.order_status.replace(/_/g, ' ')}{item.cancelled_at ? ` · cancelled ${new Date(item.cancelled_at).toLocaleString()}` : ''}</dd><dd className="text-ink/60">{item.cancellation_reason ?? `Reservation expired ${new Date(item.reservation_expires_at).toLocaleString()}`}</dd></div><div><dt className="text-ink/50">Stripe identifiers</dt><dd className="break-all">PaymentIntent: {item.provider_payment_intent_id ?? 'Unavailable'}</dd><dd className="break-all">Charge: {item.provider_charge_id ?? 'Unavailable'}</dd></div></dl><div className="mt-5 grid gap-3 md:grid-cols-3"><Field label="Resolution" htmlFor={`resolution-${item.payment_id}`}><Select id={`resolution-${item.payment_id}`} value={resolutionCode} onChange={(event) => setResolutionCode(event.target.value as LatePaymentResolutionCode)} options={LATE_PAYMENT_RESOLUTION_CODES.map((code) => ({ value: code, label: resolutionLabel(code) }))} disabled={savingPaymentId !== null} /></Field><Field label="Manual reference (optional)" htmlFor={`reference-${item.payment_id}`}><Input id={`reference-${item.payment_id}`} value={reference} maxLength={255} onChange={(event) => setReference(event.target.value)} disabled={savingPaymentId !== null} /></Field><Field label="Internal note (optional)" htmlFor={`note-${item.payment_id}`}><Textarea id={`note-${item.payment_id}`} value={note} maxLength={500} onChange={(event) => setNote(event.target.value)} disabled={savingPaymentId !== null} /></Field></div><div className="mt-4 flex flex-wrap items-center gap-3"><Button variant="destructive" onClick={() => void resolve(item)} disabled={savingPaymentId !== null}>{savingPaymentId === item.payment_id ? 'Recording…' : confirmingPaymentId === item.payment_id ? 'Confirm internal resolution' : 'Record resolution'}</Button>{confirmingPaymentId === item.payment_id ? <p className="text-sm text-amber-800">Confirm that this records an internal outcome only. Complete any refund manually in Stripe first.</p> : null}</div></article>)}</div>}
  </section>;
}
