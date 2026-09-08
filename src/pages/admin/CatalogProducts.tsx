import React, { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { Select } from '../../components/ui/select';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { listAdminProducts } from '../../repositories/adminCatalogRepository';
import type { AdminProduct } from '../../types/catalog';

export function AdminProductsPage() {
  const { roles } = useAdminAuth();
  const canManage = roles.some((role) => role === 'owner' || role === 'manager');
  const [items, setItems] = useState<AdminProduct[]>([]);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [category, setCategory] = useState('all');
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { void listAdminProducts().then(setItems).catch((cause: Error) => setError(cause.message)); }, []);
  const filtered = useMemo(() => items.filter((item) =>
    `${item.name} ${item.slug} ${item.category?.name ?? ''}`.toLowerCase().includes(query.toLowerCase()) &&
    (status === 'all' || item.status === status) && (category === 'all' || item.category_id === category)
  ), [items, query, status, category]);
  const categoryOptions = [{ value: 'all', label: 'All categories' }, ...Array.from(new Map(
    items.filter((item) => item.category).map((item) => [item.category_id, item.category?.name ?? 'Unassigned'])
  ).entries()).map(([value, label]) => ({ value, label }))];

  return <section className="space-y-6"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Catalog</p><h1 className="mt-2 font-display text-3xl font-bold">Products</h1>{!canManage ? <p className="mt-2 text-sm text-ink/60">View only - staff cannot change catalog data.</p> : null}</div>{canManage ? <Button asChild><Link to="/admin/catalog/products/new">New product</Link></Button> : null}</div><div className="grid gap-3 sm:grid-cols-3"><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search name, slug, or category" /><Select value={status} options={[{ value: 'all', label: 'All statuses' }, ...['draft', 'active', 'archived'].map((value) => ({ value, label: value }))]} onChange={(event) => setStatus(event.target.value)} /><Select value={category} options={categoryOptions} onChange={(event) => setCategory(event.target.value)} /></div>{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}<div className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Product</th><th className="p-4">Category</th><th className="p-4">Price</th><th className="p-4">Status</th><th className="p-4" /></tr></thead><tbody>{filtered.map((item) => <tr key={item.id} className="border-t border-ink/10"><td className="p-4"><strong>{item.name}</strong><span className="ml-2 text-ink/50">{item.slug}</span></td><td className="p-4">{item.category?.name}</td><td className="p-4">{item.price_on_request ? 'Price on request' : `GBP ${item.sale_price ?? item.base_price}`}</td><td className="p-4">{item.status}{item.is_available ? '' : ' - unavailable'}</td><td className="p-4 text-right"><Button asChild size="sm" variant="outline"><Link to={`/admin/catalog/products/${item.id}/edit`}>{canManage ? 'Edit' : 'View'}</Link></Button></td></tr>)}</tbody></table></div></section>;
}
