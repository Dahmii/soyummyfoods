import React, { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { listAdminInventory, listInventoryProducts, type InventoryProductOption } from '../../repositories/adminInventoryRepository';
import type { AdminInventory } from '../../types/inventory';

type InventoryAvailability = {
  label: 'Available' | 'Out of stock' | 'Problem' | 'Not tracked' | 'Not configured';
  className: string;
};

function inventoryAvailability(item: AdminInventory | undefined): InventoryAvailability {
  if (!item) return { label: 'Not configured', className: 'bg-ink/5 text-ink/60 ring-ink/10' };
  if (!item.is_tracking_enabled) return { label: 'Not tracked', className: 'bg-ink/5 text-ink/60 ring-ink/10' };

  const available = item.quantity_on_hand - item.quantity_reserved;
  if (available < 0) return { label: 'Problem', className: 'bg-red-50 text-red-800 ring-red-200' };
  if (available === 0) return { label: 'Out of stock', className: 'bg-red-50 text-red-800 ring-red-200' };
  return { label: 'Available', className: 'bg-emerald-50 text-emerald-800 ring-emerald-200' };
}

function quantity(item: AdminInventory | undefined, field: 'quantity_on_hand' | 'quantity_reserved'): number | '—' {
  return item?.is_tracking_enabled ? item[field] : '—';
}

function availableQuantity(item: AdminInventory | undefined): number | '—' {
  return item?.is_tracking_enabled ? item.quantity_on_hand - item.quantity_reserved : '—';
}

function AvailabilityBadge({ item }: { item: AdminInventory | undefined }) {
  const status = inventoryAvailability(item);
  return <span className={`inline-flex w-fit rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset ${status.className}`}>{status.label}</span>;
}

export function AdminInventoryListPage() {
  const [inventory, setInventory] = useState<AdminInventory[]>([]);
  const [products, setProducts] = useState<InventoryProductOption[]>([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [rows, productRows] = await Promise.all([listAdminInventory(), listInventoryProducts()]);
      setInventory(rows);
      setProducts(productRows);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load inventory.');
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const normalized = query.trim().toLowerCase();
  const configured = new Map(inventory.map((item) => [item.product_id, item]));
  const rows = products.filter((product) => !normalized || product.name.toLowerCase().includes(normalized) || product.slug.toLowerCase().includes(normalized)).map((product) => ({ product, inventory: configured.get(product.id) }));
  return <section className="space-y-6"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Operations</p><h1 className="mt-2 font-display text-3xl font-bold">Inventory</h1><p className="mt-2 text-sm text-ink/60">On hand is physical sellable portions. Reserved portions are committed to pending-payment orders; available is what remains for new orders.</p></div>{loading ? <p className="text-sm text-ink/60">Loading inventory…</p> : error ? <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800" role="alert"><p>Could not load inventory: {error}</p><Button size="sm" variant="outline" className="mt-3" onClick={() => void load()}>Retry</Button></div> : <><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search products" />{rows.length === 0 ? <div className="rounded-2xl border border-dashed border-ink/20 bg-white p-6 text-sm text-ink/60">No products match this inventory view.</div> : <><div className="space-y-3 md:hidden">{rows.map(({ product, inventory: item }) => <article key={product.id} className="rounded-2xl border border-ink/10 bg-white p-4"><div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold text-ink">{product.name}</h2><p className="mt-1 text-xs text-ink/50">{product.slug} · {product.status}</p></div><AvailabilityBadge item={item} /></div><dl className="mt-4 grid grid-cols-3 gap-3 text-sm"><div><dt className="text-xs font-medium uppercase tracking-[.08em] text-ink/50">On hand</dt><dd className="mt-1 font-semibold">{quantity(item, 'quantity_on_hand')}</dd></div><div><dt className="text-xs font-medium uppercase tracking-[.08em] text-ink/50">Reserved</dt><dd className={`mt-1 font-semibold ${item?.is_tracking_enabled && item.quantity_reserved > 0 ? 'text-amber-800' : ''}`}>{quantity(item, 'quantity_reserved')}</dd></div><div><dt className="text-xs font-medium uppercase tracking-[.08em] text-ink/50">Available</dt><dd className={`mt-1 font-semibold ${typeof availableQuantity(item) === 'number' && availableQuantity(item) <= 0 ? 'text-red-800' : ''}`}>{availableQuantity(item)}</dd></div></dl><div className="mt-4 flex justify-end"><Button asChild size="sm" variant="outline"><Link to={`/admin/inventory/${product.id}`}>{item ? 'View' : 'Configure'}</Link></Button></div></article>)}</div><div className="hidden overflow-x-auto rounded-2xl border border-ink/10 bg-white md:block"><table className="min-w-[760px] w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Product</th><th className="p-4">On hand</th><th className="p-4">Reserved</th><th className="p-4">Available</th><th className="p-4">Status</th><th className="p-4" /></tr></thead><tbody>{rows.map(({ product, inventory: item }) => { const available = availableQuantity(item); return <tr key={product.id} className="border-t border-ink/10"><td className="p-4"><strong>{product.name}</strong><span className="ml-2 text-ink/50">{product.slug}</span><span className="ml-2 text-xs capitalize text-ink/45">{product.status}</span></td><td className="p-4 font-medium">{quantity(item, 'quantity_on_hand')}</td><td className={`p-4 font-medium ${item?.is_tracking_enabled && item.quantity_reserved > 0 ? 'text-amber-800' : ''}`}>{quantity(item, 'quantity_reserved')}</td><td className={`p-4 font-semibold ${typeof available === 'number' && available <= 0 ? 'text-red-800' : ''}`}>{available}</td><td className="p-4"><AvailabilityBadge item={item} /></td><td className="p-4 text-right"><Button asChild size="sm" variant="outline"><Link to={`/admin/inventory/${product.id}`}>{item ? 'View' : 'Configure'}</Link></Button></td></tr>; })}</tbody></table></div></>}</>}</section>;
}
