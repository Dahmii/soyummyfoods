import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import * as Dialog from '@radix-ui/react-dialog';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { Select } from '../../components/ui/select';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { getAdminProductRemovalPlan, listAdminProducts, removeAdminProduct } from '../../repositories/adminCatalogRepository';
import type { AdminProduct, ProductRemovalPlan } from '../../types/catalog';

export function AdminProductsPage() {
  const { roles } = useAdminAuth();
  const canManage = roles.some((role) => role === 'owner' || role === 'manager');
  const [items, setItems] = useState<AdminProduct[]>([]);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('all');
  const [category, setCategory] = useState('all');
  const [error, setError] = useState<string | null>(null);
  const [removalTarget, setRemovalTarget] = useState<AdminProduct | null>(null);
  const [removalPlan, setRemovalPlan] = useState<ProductRemovalPlan | null>(null);
  const [removalError, setRemovalError] = useState<string | null>(null);
  const [loadingRemovalPlan, setLoadingRemovalPlan] = useState(false);
  const [removingProductId, setRemovingProductId] = useState<string | null>(null);
  const [removalNotice, setRemovalNotice] = useState<string | null>(null);
  const removalPlanRequestId = useRef(0);

  const load = useCallback(async () => {
    setError(null);
    try {
      setItems(await listAdminProducts());
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load products.');
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function openRemovalDialog(product: AdminProduct) {
    const requestId = removalPlanRequestId.current + 1;
    removalPlanRequestId.current = requestId;
    setRemovalTarget(product);
    setRemovalPlan(null);
    setRemovalError(null);
    setLoadingRemovalPlan(true);
    try {
      const plan = await getAdminProductRemovalPlan(product.id);
      if (requestId === removalPlanRequestId.current) setRemovalPlan(plan);
    } catch (cause) {
      if (requestId === removalPlanRequestId.current) {
        setRemovalError(cause instanceof Error ? cause.message : 'Could not check whether this product can be removed safely.');
      }
    } finally {
      if (requestId === removalPlanRequestId.current) setLoadingRemovalPlan(false);
    }
  }

  function closeRemovalDialog() {
    if (removingProductId === null) {
      removalPlanRequestId.current += 1;
      setRemovalTarget(null);
    }
  }

  async function confirmRemoval() {
    if (!removalTarget || !removalPlan || removingProductId !== null) return;
    setRemovingProductId(removalTarget.id);
    setRemovalError(null);
    try {
      const result = await removeAdminProduct(removalTarget.id);
      setRemovalTarget(null);
      setRemovalNotice(result === 'deleted'
        ? `${removalTarget.name} was permanently deleted.`
        : `${removalTarget.name} was archived and marked unavailable to preserve its history.`);
      await load();
    } catch (cause) {
      setRemovalError(cause instanceof Error ? cause.message : 'Could not remove this product.');
    } finally {
      setRemovingProductId(null);
    }
  }
  const filtered = useMemo(() => items.filter((item) =>
    `${item.name} ${item.slug} ${item.category?.name ?? ''}`.toLowerCase().includes(query.toLowerCase()) &&
    (status === 'all' || item.status === status) && (category === 'all' || item.category_id === category)
  ), [items, query, status, category]);
  const categoryOptions = [{ value: 'all', label: 'All categories' }, ...Array.from(new Map(
    items.filter((item) => item.category).map((item) => [item.category_id, item.category?.name ?? 'Unassigned'])
  ).entries()).map(([value, label]) => ({ value, label }))];

  return <section className="space-y-6"><div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Catalog</p><h1 className="mt-2 font-display text-3xl font-bold">Products</h1>{!canManage ? <p className="mt-2 text-sm text-ink/60">View only - staff cannot change catalog data.</p> : null}</div>{canManage ? <Button asChild><Link to="/admin/catalog/products/new">New product</Link></Button> : null}</div><div className="grid gap-3 sm:grid-cols-3"><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search name, slug, or category" /><Select value={status} options={[{ value: 'all', label: 'All statuses' }, ...['draft', 'active', 'archived'].map((value) => ({ value, label: value }))]} onChange={(event) => setStatus(event.target.value)} /><Select value={category} options={categoryOptions} onChange={(event) => setCategory(event.target.value)} /></div>{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}{removalNotice ? <p role="status" className="rounded-xl bg-brand-50 p-3 text-sm text-brand-700">{removalNotice}</p> : null}<div className="overflow-x-auto rounded-2xl border border-ink/10 bg-white"><table className="w-full min-w-[46rem] text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Product</th><th className="p-4">Category</th><th className="p-4">Price</th><th className="p-4">Status</th><th className="p-4" /></tr></thead><tbody>{filtered.map((item) => <tr key={item.id} className="border-t border-ink/10"><td className="p-4"><strong>{item.name}</strong><span className="ml-2 text-ink/50">{item.slug}</span></td><td className="p-4">{item.category?.name}</td><td className="p-4">{item.price_on_request ? 'Price on request' : `GBP ${item.sale_price ?? item.base_price}`}</td><td className="p-4">{item.status}{item.is_available ? '' : ' - unavailable'}</td><td className="p-4"><div className="flex justify-end gap-2"><Button asChild size="sm" variant="outline"><Link to={`/admin/catalog/products/${item.id}/edit`}>{canManage ? 'Edit' : 'View'}</Link></Button>{canManage ? <Button type="button" size="sm" variant="ghost" onClick={() => void openRemovalDialog(item)} disabled={removingProductId !== null}>Delete</Button> : null}</div></td></tr>)}</tbody></table></div><Dialog.Root open={removalTarget !== null} onOpenChange={(open) => { if (!open) closeRemovalDialog(); }}><Dialog.Portal><Dialog.Overlay className="fixed inset-0 z-50 bg-ink/50 backdrop-blur-sm" /><Dialog.Content className="fixed inset-x-4 top-1/2 z-50 max-h-[calc(100dvh-2rem)] w-auto max-w-md -translate-y-1/2 overflow-y-auto rounded-2xl bg-cream p-6 shadow-lift outline-none sm:left-1/2 sm:right-auto sm:w-full sm:-translate-x-1/2"><Dialog.Title className="font-display text-2xl font-bold">Remove {removalTarget?.name}?</Dialog.Title><Dialog.Description className="mt-2 text-sm leading-6 text-ink/65">This action cannot be undone when the product has no operational history or stock to preserve.</Dialog.Description><div className="mt-5 rounded-xl border border-ink/10 bg-white p-4 text-sm leading-6 text-ink/70">{loadingRemovalPlan ? 'Checking whether this product has order, inventory, or stock history…' : removalPlan === 'archive' ? <>This product has historical order or inventory records, or stock that must be retained. It will be <strong className="text-ink">archived</strong> and marked unavailable; those records and uploaded image files will be preserved.</> : removalPlan === 'delete' ? <>This product has no order-item or inventory-movement history and no stock to retain. It will be <strong className="text-ink">permanently deleted</strong>, including its empty inventory configuration and image metadata. Uploaded image files will not be deleted from Storage.</> : 'The removal action could not be determined.'}</div>{removalError ? <p role="alert" className="mt-4 text-sm text-red-700">{removalError}</p> : null}<div className="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end"><Dialog.Close asChild><Button type="button" variant="outline" disabled={removingProductId !== null}>Cancel</Button></Dialog.Close><Button type="button" variant="dark" onClick={() => void confirmRemoval()} disabled={loadingRemovalPlan || removalPlan === null || removingProductId !== null}>{removingProductId === removalTarget?.id ? 'Removing…' : removalPlan === 'archive' ? 'Archive product' : 'Delete product'}</Button></div></Dialog.Content></Dialog.Portal></Dialog.Root></section>;
}
