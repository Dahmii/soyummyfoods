import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { listAdminInventory, listInventoryProducts, type InventoryProductOption } from '../../repositories/adminInventoryRepository';
import type { AdminInventory } from '../../types/inventory';

export function AdminInventoryListPage() {
  const [inventory, setInventory] = useState<AdminInventory[]>([]);
  const [products, setProducts] = useState<InventoryProductOption[]>([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { void Promise.all([listAdminInventory(), listInventoryProducts()]).then(([rows, productRows]) => { setInventory(rows); setProducts(productRows); }).catch((cause: Error) => setError(cause.message)); }, []);
  const normalized = query.trim().toLowerCase();
  const configured = new Map(inventory.map((item) => [item.product_id, item]));
  const rows = products.filter((product) => !normalized || product.name.toLowerCase().includes(normalized) || product.slug.toLowerCase().includes(normalized)).map((product) => ({ product, inventory: configured.get(product.id) }));
  return <section className="space-y-6"><div><p className="text-xs font-semibold uppercase tracking-[.16em] text-brand-500">Operations</p><h1 className="mt-2 font-display text-3xl font-bold">Inventory</h1><p className="mt-2 text-sm text-ink/60">Stock is tracked in sellable portions. Inventory changes are recorded in an immutable ledger.</p></div><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search products" />{error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}<div className="overflow-hidden rounded-2xl border border-ink/10 bg-white"><table className="w-full text-left text-sm"><thead className="bg-cream-dark text-ink/60"><tr><th className="p-4">Product</th><th className="p-4">Status</th><th className="p-4">Tracking</th><th className="p-4">Quantity</th><th className="p-4">Low-stock threshold</th><th className="p-4" /></tr></thead><tbody>{rows.map(({ product, inventory: item }) => { const low = item?.is_tracking_enabled && item.low_stock_threshold !== null && item.quantity_on_hand <= item.low_stock_threshold; return <tr key={product.id} className="border-t border-ink/10"><td className="p-4"><strong>{product.name}</strong><span className="ml-2 text-ink/50">{product.slug}</span></td><td className="p-4">{product.status}</td><td className="p-4">{item ? item.is_tracking_enabled ? 'Enabled' : 'Disabled' : 'Not configured'}</td><td className="p-4">{item ? item.quantity_on_hand : '—'}{low ? <span className="ml-2 text-xs font-semibold text-red-700">{item.quantity_on_hand === 0 ? 'Out of stock' : 'Low'}</span> : null}</td><td className="p-4">{item?.low_stock_threshold ?? '—'}</td><td className="p-4 text-right"><Button asChild size="sm" variant="outline"><Link to={`/admin/inventory/${product.id}`}>{item ? 'View' : 'Configure'}</Link></Button></td></tr>; })}</tbody></table></div></section>;
}
