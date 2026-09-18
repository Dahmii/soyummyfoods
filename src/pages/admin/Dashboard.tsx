import { Link, useOutletContext } from 'react-router-dom';
import { ArrowUpRightIcon, BoxesIcon, ClipboardListIcon, CreditCardIcon, PackageIcon } from 'lucide-react';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import type { AdminOperationalAwareness } from '../../hooks/useAdminOperationalAwareness';
import type { AdminActionableOrder, AdminActionableOrderStatus } from '../../types/adminOrders';
import { formatPrice } from '../../utils/currency';

const DASHBOARD_LINKS = [
  { to: '/admin/orders', title: 'Orders', description: 'Manage and fulfil customer orders.', icon: ClipboardListIcon, restricted: false },
  { to: '/admin/inventory', title: 'Inventory', description: 'Review stock and availability.', icon: BoxesIcon, restricted: false },
  { to: '/admin/catalog/products', title: 'Products', description: 'Manage menu items and availability.', icon: PackageIcon, restricted: false },
  { to: '/admin/payments/reconciliation', title: 'Payments', description: 'Review payment operations.', icon: CreditCardIcon, restricted: true }
];

const ACTIONABLE_STATUS_STYLES: Record<AdminActionableOrderStatus, string> = {
  confirmed: 'bg-brand-50 text-brand-700 ring-brand-100',
  preparing: 'bg-amber-50 text-amber-800 ring-amber-100',
  ready: 'bg-emerald-50 text-emerald-800 ring-emerald-100'
};

function formatStatus(status: AdminActionableOrderStatus): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function formatOrderAge(createdAt: string): string {
  const createdAtMs = new Date(createdAt).getTime();
  if (Number.isNaN(createdAtMs)) return 'Time unavailable';

  const elapsedMs = Math.max(0, Date.now() - createdAtMs);
  const elapsedMinutes = Math.floor(elapsedMs / 60_000);
  if (elapsedMinutes < 1) return 'Just now';
  if (elapsedMinutes < 60) return `${elapsedMinutes} min ago`;

  const elapsedHours = Math.floor(elapsedMinutes / 60);
  if (elapsedHours < 48) return `${elapsedHours} hr ago`;

  return new Intl.DateTimeFormat('en-GB', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit'
  }).format(new Date(createdAt));
}

function ActionableOrderRow({ order }: { order: AdminActionableOrder }) {
  return <Link to={`/admin/orders/${order.id}`} className="group grid gap-3 rounded-xl border border-ink/10 bg-white px-4 py-3 shadow-sm transition-colors hover:border-brand-200 hover:bg-brand-50/35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 sm:grid-cols-[minmax(0,1fr)_auto_auto] sm:items-center">
    <div className="min-w-0">
      <p className="truncate text-sm font-semibold text-ink">{order.order_number}</p>
      <p className="mt-0.5 text-xs text-ink/55">{formatOrderAge(order.created_at)}</p>
    </div>
    <span className={`inline-flex w-fit rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset ${ACTIONABLE_STATUS_STYLES[order.status]}`}>{formatStatus(order.status)}</span>
    <span className="text-sm font-semibold text-ink sm:text-right">{formatPrice(Number(order.total))} <span className="text-xs font-medium text-ink/50">{order.currency_code}</span></span>
  </Link>;
}

export function AdminDashboardPage() {
  const { roles } = useAdminAuth();
  const { actionableOrders, error, isLoading, refresh } = useOutletContext<AdminOperationalAwareness>();
  const canReconcilePayments = roles.some((role) => role === 'owner' || role === 'manager');
  const links = DASHBOARD_LINKS.filter((link) => !link.restricted || canReconcilePayments);

  return (
    <section className="max-w-5xl">
      <section aria-labelledby="orders-needing-attention">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 id="orders-needing-attention" className="font-display text-xl font-bold text-ink">Orders needing attention</h2>
            <p className="mt-1 text-sm text-ink/60">Confirmed, preparing and ready orders in oldest-first order.</p>
          </div>
          <Link to="/admin/orders" className="text-sm font-semibold text-brand-700 hover:text-brand-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2">View all orders</Link>
        </div>
        <div className="mt-4 space-y-2">
          {isLoading ? Array.from({ length: 3 }, (_, index) => <div key={index} className="h-[4.5rem] animate-pulse rounded-xl border border-ink/10 bg-white/70" aria-hidden="true" />) : null}
          {!isLoading && actionableOrders.map((order) => <ActionableOrderRow key={order.id} order={order} />)}
          {!isLoading && actionableOrders.length === 0 && !error ? <div className="rounded-xl border border-dashed border-ink/15 bg-white/60 px-4 py-5 text-sm text-ink/60">No confirmed, preparing or ready orders need attention right now.</div> : null}
          {error ? <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900" role="status">Unable to refresh the operational queue. Existing order information remains visible where available. <button type="button" className="ml-1 font-semibold underline underline-offset-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500" onClick={() => void refresh()}>Retry</button></div> : null}
        </div>
      </section>

      <section className="mt-8">
      <div>
        <h2 className="font-display text-xl font-bold text-ink">Quick access</h2>
        <p className="mt-1 text-sm text-ink/60">Common areas for managing your store.</p>
      </div>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        {links.map(({ to, title, description, icon: Icon }) => <Link key={to} to={to} className="group rounded-xl border border-ink/10 bg-white p-4 shadow-sm transition-colors hover:border-brand-200 hover:bg-brand-50/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"><div className="flex items-start justify-between gap-4"><span className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-50 text-brand-700"><Icon className="h-4 w-4" aria-hidden="true" /></span><ArrowUpRightIcon className="h-4 w-4 text-ink/35 transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-brand-600" aria-hidden="true" /></div><h3 className="mt-4 text-sm font-semibold text-ink">{title}</h3><p className="mt-1 text-sm leading-relaxed text-ink/60">{description}</p></Link>)}
      </div>
      </section>
    </section>
  );
}
