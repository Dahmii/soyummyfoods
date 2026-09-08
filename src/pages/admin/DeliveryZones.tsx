import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { listAdminDeliveryZones } from '../../repositories/adminBusinessDeliveryRepository';
import type { AdminDeliveryZone } from '../../types/business';

export function AdminDeliveryZonesPage() {
  const { roles } = useAdminAuth();
  const canManage = roles.some((role) => role === 'owner' || role === 'manager');
  const [items, setItems] = useState<AdminDeliveryZone[]>([]);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { void listAdminDeliveryZones().then(setItems).catch((cause: Error) => setError(cause.message)); }, []);
  return <section className="space-y-6"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Delivery</p><h1 className="mt-2 font-display text-3xl font-bold">Delivery zones</h1>{!canManage ? <p className="mt-2 text-sm text-ink/60">View only — staff cannot change delivery zones.</p> : null}</div>{canManage ? <Button asChild><Link to="/admin/delivery-zones/new">New delivery zone</Link></Button> : null}</div>{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}<div className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Zone</th><th className="p-4">Prefixes</th><th className="p-4">Fee</th><th className="p-4">Priority</th><th className="p-4">Status</th><th className="p-4" /></tr></thead><tbody>{items.map((zone) => <tr key={zone.id} className="border-t border-ink/10"><td className="p-4"><strong>{zone.name}</strong></td><td className="p-4">{zone.postcode_prefixes.join(', ')}</td><td className="p-4">GBP {zone.delivery_fee}</td><td className="p-4">{zone.match_priority}</td><td className="p-4">{zone.is_active ? 'Active' : 'Inactive'}</td><td className="p-4 text-right"><Button asChild size="sm" variant="outline"><Link to={`/admin/delivery-zones/${zone.id}/edit`}>{canManage ? 'Edit' : 'View'}</Link></Button></td></tr>)}</tbody></table>{items.length === 0 ? <p className="p-5 text-sm text-ink/60">No delivery zones configured.</p> : null}</div></section>;
}
