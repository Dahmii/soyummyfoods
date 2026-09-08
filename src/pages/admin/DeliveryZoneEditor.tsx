import React, { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Field, Input, Textarea } from '../../components/ui/input';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { getAdminDeliveryZone, saveDeliveryZone } from '../../repositories/adminBusinessDeliveryRepository';
import { deliveryZoneInputSchema, parsePostcodePrefixes, type DeliveryZoneInput } from '../../types/business';

const blank: DeliveryZoneInput = { name: '', is_active: true, postcode_prefixes: [], delivery_fee: 0, minimum_order: null, match_priority: 0, display_order: 0 };
type DeliveryZoneForm = Omit<DeliveryZoneInput, 'delivery_fee' | 'match_priority' | 'display_order'> & {
  delivery_fee: number | '';
  match_priority: number | '';
  display_order: number | '';
};

function toRequiredNumber(value: string): number | '' {
  return value === '' ? '' : Number(value);
}

export function AdminDeliveryZoneEditorPage() {
  const { zoneId } = useParams(); const navigate = useNavigate(); const { roles } = useAdminAuth();
  const canManage = roles.some((role) => role === 'owner' || role === 'manager');
  const [form, setForm] = useState<DeliveryZoneForm>(blank); const [prefixText, setPrefixText] = useState('');
  const [error, setError] = useState<string | null>(null); const [loaded, setLoaded] = useState(!zoneId);
  useEffect(() => { if (zoneId) void getAdminDeliveryZone(zoneId).then((zone) => { setForm({ name: zone.name, is_active: zone.is_active, postcode_prefixes: zone.postcode_prefixes, delivery_fee: zone.delivery_fee, minimum_order: zone.minimum_order, match_priority: zone.match_priority, display_order: zone.display_order }); setPrefixText(zone.postcode_prefixes.join('\n')); setLoaded(true); }).catch((cause: Error) => { setError(cause.message); setLoaded(true); }); }, [zoneId]);
  async function submit(event: React.FormEvent) { event.preventDefault(); setError(null); const parsed = deliveryZoneInputSchema.safeParse({ ...form, postcode_prefixes: parsePostcodePrefixes(prefixText) }); if (!parsed.success) { setError(parsed.error.issues[0]?.message ?? 'Check the delivery-zone fields.'); return; } try { await saveDeliveryZone(parsed.data, zoneId); navigate('/admin/delivery-zones'); } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not save delivery zone.'); } }
  if (!loaded) return <p>Loading delivery zone…</p>;
  const disabled = !canManage;
  return <section className="space-y-7"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Delivery</p><h1 className="mt-2 font-display text-3xl font-bold">{zoneId ? 'Edit delivery zone' : 'New delivery zone'}</h1>{disabled ? <p className="mt-2 text-sm text-ink/60">View only — staff cannot change delivery zones.</p> : null}</div>{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}<form onSubmit={submit} className="grid gap-4 rounded-2xl border border-ink/10 bg-white p-5 sm:grid-cols-2"><Field label="Zone name" htmlFor="delivery-zone-name"><Input id="delivery-zone-name" value={form.name} disabled={disabled} onChange={(event) => setForm({ ...form, name: event.target.value })} required /></Field><label className="flex items-end gap-2 pb-3 text-sm"><input type="checkbox" checked={form.is_active} disabled={disabled} onChange={(event) => setForm({ ...form, is_active: event.target.checked })} /> Active</label><Field label="Postcode prefixes" htmlFor="delivery-zone-prefixes" className="sm:col-span-2"><Textarea id="delivery-zone-prefixes" value={prefixText} disabled={disabled} onChange={(event) => setPrefixText(event.target.value)} placeholder={'SE1\nSE11'} required /></Field><p className="-mt-2 text-xs text-ink/50 sm:col-span-2">One prefix per line or comma-separated. Spaces and case are normalized when saved.</p><Field label="Delivery fee (GBP)" htmlFor="delivery-zone-fee"><Input id="delivery-zone-fee" type="number" min="0" step="0.01" value={form.delivery_fee} disabled={disabled} onChange={(event) => setForm({ ...form, delivery_fee: toRequiredNumber(event.target.value) })} /></Field><Field label="Minimum order (optional, GBP)" htmlFor="delivery-zone-minimum"><Input id="delivery-zone-minimum" type="number" min="0" step="0.01" value={form.minimum_order ?? ''} disabled={disabled} onChange={(event) => setForm({ ...form, minimum_order: event.target.value === '' ? null : Number(event.target.value) })} /></Field><Field label="Match priority" htmlFor="delivery-zone-priority"><Input id="delivery-zone-priority" type="number" min="0" value={form.match_priority} disabled={disabled} onChange={(event) => setForm({ ...form, match_priority: toRequiredNumber(event.target.value) })} /></Field><Field label="Display order" htmlFor="delivery-zone-order"><Input id="delivery-zone-order" type="number" min="0" value={form.display_order} disabled={disabled} onChange={(event) => setForm({ ...form, display_order: toRequiredNumber(event.target.value) })} /></Field>{canManage ? <div className="flex gap-2 sm:col-span-2"><Button type="submit">Save delivery zone</Button><Button asChild variant="ghost"><Link to="/admin/delivery-zones">Cancel</Link></Button></div> : <div className="sm:col-span-2"><Button asChild variant="ghost"><Link to="/admin/delivery-zones">Back to delivery zones</Link></Button></div>}</form></section>;
}
