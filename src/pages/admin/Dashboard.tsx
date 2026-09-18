import { Link } from 'react-router-dom';
import { ArrowUpRightIcon, BoxesIcon, ClipboardListIcon, CreditCardIcon, PackageIcon } from 'lucide-react';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';

const DASHBOARD_LINKS = [
  { to: '/admin/orders', title: 'Orders', description: 'Manage and fulfil customer orders.', icon: ClipboardListIcon, restricted: false },
  { to: '/admin/inventory', title: 'Inventory', description: 'Review stock and availability.', icon: BoxesIcon, restricted: false },
  { to: '/admin/catalog/products', title: 'Products', description: 'Manage menu items and availability.', icon: PackageIcon, restricted: false },
  { to: '/admin/payments/reconciliation', title: 'Payments', description: 'Review payment operations.', icon: CreditCardIcon, restricted: true }
];

export function AdminDashboardPage() {
  const { roles } = useAdminAuth();
  const canReconcilePayments = roles.some((role) => role === 'owner' || role === 'manager');
  const links = DASHBOARD_LINKS.filter((link) => !link.restricted || canReconcilePayments);

  return (
    <section className="max-w-5xl">
      <div>
        <h2 className="font-display text-xl font-bold text-ink">Quick access</h2>
        <p className="mt-1 text-sm text-ink/60">Common areas for managing your store.</p>
      </div>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        {links.map(({ to, title, description, icon: Icon }) => <Link key={to} to={to} className="group rounded-xl border border-ink/10 bg-white p-4 shadow-sm transition-colors hover:border-brand-200 hover:bg-brand-50/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"><div className="flex items-start justify-between gap-4"><span className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-50 text-brand-700"><Icon className="h-4 w-4" aria-hidden="true" /></span><ArrowUpRightIcon className="h-4 w-4 text-ink/35 transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-brand-600" aria-hidden="true" /></div><h3 className="mt-4 text-sm font-semibold text-ink">{title}</h3><p className="mt-1 text-sm leading-relaxed text-ink/60">{description}</p></Link>)}
      </div>
    </section>
  );
}
