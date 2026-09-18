import { useEffect, useMemo, useState } from 'react';
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BoxesIcon,
  ChevronRightIcon,
  ClipboardListIcon,
  CreditCardIcon,
  LayoutDashboardIcon,
  MapPinnedIcon,
  MenuIcon,
  PackageIcon,
  SettingsIcon,
  TagsIcon,
  XIcon
} from 'lucide-react';
import { Button } from '../ui/button';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';
import { useAdminOperationalAwareness } from '../../hooks/useAdminOperationalAwareness';
import { cn } from '../../utils/cn';

type NavigationItem = {
  to: string;
  label: string;
  icon: typeof LayoutDashboardIcon;
  exact?: boolean;
  restricted?: boolean;
};

type NavigationGroup = {
  label?: string;
  items: NavigationItem[];
};

const NAVIGATION: NavigationGroup[] = [
  { items: [{ to: '/admin', label: 'Dashboard', icon: LayoutDashboardIcon, exact: true }] },
  {
    label: 'Operations',
    items: [
      { to: '/admin/orders', label: 'Orders', icon: ClipboardListIcon },
      { to: '/admin/inventory', label: 'Inventory', icon: BoxesIcon }
    ]
  },
  {
    label: 'Catalog',
    items: [
      { to: '/admin/catalog/products', label: 'Products', icon: PackageIcon },
      { to: '/admin/catalog/categories', label: 'Categories', icon: TagsIcon }
    ]
  },
  {
    label: 'Business',
    items: [
      { to: '/admin/payments/reconciliation', label: 'Payments', icon: CreditCardIcon, restricted: true },
      { to: '/admin/delivery-zones', label: 'Delivery zones', icon: MapPinnedIcon },
      { to: '/admin/settings/business', label: 'Business settings', icon: SettingsIcon }
    ]
  }
];

function getPageMeta(pathname: string) {
  if (pathname.startsWith('/admin/orders/')) return { title: 'Order details', description: 'Review fulfilment and payment information.' };
  if (pathname === '/admin/orders') return { title: 'Orders', description: 'Manage and fulfil customer orders.' };
  if (pathname.startsWith('/admin/inventory/')) return { title: 'Inventory item', description: 'Configure stock and record movements.' };
  if (pathname === '/admin/inventory') return { title: 'Inventory', description: 'Review stock and availability.' };
  if (pathname.startsWith('/admin/catalog/products/new')) return { title: 'New product', description: 'Add a menu item to the catalogue.' };
  if (pathname.startsWith('/admin/catalog/products/')) return { title: 'Edit product', description: 'Update catalogue details and images.' };
  if (pathname === '/admin/catalog/products') return { title: 'Products', description: 'Manage menu items and availability.' };
  if (pathname === '/admin/catalog/categories') return { title: 'Categories', description: 'Organise the menu catalogue.' };
  if (pathname.startsWith('/admin/delivery-zones/new')) return { title: 'New delivery zone', description: 'Configure delivery coverage and fees.' };
  if (pathname.startsWith('/admin/delivery-zones/')) return { title: 'Edit delivery zone', description: 'Update delivery coverage and fees.' };
  if (pathname === '/admin/delivery-zones') return { title: 'Delivery zones', description: 'Manage delivery coverage and fees.' };
  if (pathname === '/admin/payments/reconciliation') return { title: 'Payments', description: 'Review payment reconciliation work.' };
  if (pathname === '/admin/settings/business') return { title: 'Business settings', description: 'Maintain your business and tax details.' };
  return { title: 'Dashboard', description: 'Overview of your SoYummy operations.' };
}

function roleLabel(roles: string[]) {
  return roles.length === 0 ? 'Administrator' : roles.map((role) => role.charAt(0).toUpperCase() + role.slice(1)).join(', ');
}

function initials(email?: string) {
  const localPart = email?.split('@')[0]?.trim() || 'SY';
  const pieces = localPart.split(/[._-]+/).filter(Boolean);
  return pieces.length > 1
    ? pieces.slice(0, 2).map((piece) => piece.charAt(0)).join('').toUpperCase()
    : localPart.slice(0, 2).toUpperCase();
}

export function AdminLayout() {
  const { pathname } = useLocation();
  const { roles, session, signOut } = useAdminAuth();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const operationalAwareness = useAdminOperationalAwareness();
  const canReconcilePayments = roles.some((role) => role === 'owner' || role === 'manager');
  const pageMeta = useMemo(() => getPageMeta(pathname), [pathname]);
  const visibleNavigation = useMemo(
    () => NAVIGATION.map((group) => ({
      ...group,
      items: group.items.filter((item) => !item.restricted || canReconcilePayments)
    })).filter((group) => group.items.length > 0),
    [canReconcilePayments]
  );

  useEffect(() => {
    setIsMenuOpen(false);
  }, [pathname]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') setIsMenuOpen(false);
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  return (
    <div className="min-h-screen bg-[#f7f5f1] text-ink">
      <aside className="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col border-r border-ink/10 bg-white lg:flex">
        <SidebarContent navigation={visibleNavigation} confirmedOrderCount={operationalAwareness.confirmedOrderCount} onNavigate={() => setIsMenuOpen(false)} />
      </aside>

      {isMenuOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button type="button" aria-label="Close navigation menu" className="absolute inset-0 bg-ink/35" onClick={() => setIsMenuOpen(false)} />
          <aside aria-label="Admin navigation" className="relative flex h-full w-[min(18rem,calc(100vw-3.5rem))] flex-col bg-white shadow-2xl">
            <SidebarContent navigation={visibleNavigation} confirmedOrderCount={operationalAwareness.confirmedOrderCount} onNavigate={() => setIsMenuOpen(false)} onClose={() => setIsMenuOpen(false)} />
          </aside>
        </div>
      ) : null}

      <div className="min-h-screen lg:pl-64">
        <header className="sticky top-0 z-30 border-b border-ink/10 bg-white/95 backdrop-blur">
          <div className="flex min-h-14 items-center justify-between gap-3 px-4 sm:px-6 lg:px-8">
            <div className="flex min-w-0 items-center gap-3">
              <button type="button" className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-ink transition-colors hover:bg-ink/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 lg:hidden" aria-label="Open navigation menu" aria-expanded={isMenuOpen} onClick={() => setIsMenuOpen(true)}>
                <MenuIcon className="h-5 w-5" aria-hidden="true" />
              </button>
              <div className="min-w-0">
                <h1 className="truncate font-display text-lg font-bold text-ink sm:text-xl">{pageMeta.title}</h1>
                <p className="hidden truncate text-sm text-ink/55 sm:block">{pageMeta.description}</p>
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2 sm:gap-3">
              <div className="flex items-center gap-2 rounded-full bg-[#f7f5f1] px-2 py-1.5 sm:pl-2 sm:pr-3">
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-500 text-xs font-bold text-white" aria-hidden="true">{initials(session?.user.email)}</span>
                <span className="hidden text-left sm:block"><span className="block text-xs font-semibold text-ink">{roleLabel(roles)}</span><span className="block text-[11px] text-ink/50">Account</span></span>
              </div>
              <Button size="sm" variant="outline" className="px-3" onClick={() => void signOut()}>Log out</Button>
            </div>
          </div>
        </header>
        <main data-admin-content className="mx-auto w-full max-w-[96rem] px-4 py-5 sm:px-6 lg:px-8 lg:py-6">
          <Outlet context={operationalAwareness} />
        </main>
      </div>
    </div>
  );
}

function SidebarContent({ navigation, confirmedOrderCount, onNavigate, onClose }: { navigation: NavigationGroup[]; confirmedOrderCount: number; onNavigate: () => void; onClose?: () => void }) {
  return (
    <>
      <div className="flex h-20 shrink-0 items-center justify-between border-b border-ink/10 px-5">
        <Link to="/admin" className="leading-tight" onClick={onNavigate}>
          <span className="block font-display text-xl font-bold text-ink">SoYummy Foods</span>
          <span className="mt-0.5 block text-[11px] font-semibold uppercase tracking-[.18em] text-brand-600">Admin</span>
        </Link>
        {onClose ? <button type="button" className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-ink hover:bg-ink/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500" aria-label="Close navigation menu" onClick={onClose}><XIcon className="h-5 w-5" aria-hidden="true" /></button> : null}
      </div>
      <nav aria-label="Admin navigation" className="scrollbar-thin min-h-0 flex-1 overflow-y-auto px-3 py-5">
        {navigation.map((group, index) => (
          <div key={group.label ?? 'dashboard'} className={index === 0 ? '' : 'mt-6'}>
            {group.label ? <p className="mb-2 px-3 text-[11px] font-semibold uppercase tracking-[.16em] text-ink/45">{group.label}</p> : null}
            <ul className="space-y-1">
              {group.items.map((item) => {
                const Icon = item.icon;
                const showConfirmedOrderCount = item.to === '/admin/orders' && confirmedOrderCount > 0;
                return <li key={item.to}><NavLink to={item.to} end={item.exact} onClick={onNavigate} className={({ isActive }) => cn('flex min-h-10 items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500', isActive ? 'bg-brand-50 text-brand-700' : 'text-ink/70 hover:bg-ink/5 hover:text-ink')}><Icon className="h-4 w-4 shrink-0" aria-hidden="true" /><span>{item.label}</span>{showConfirmedOrderCount ? <span className="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-brand-600 px-1.5 py-0.5 text-[11px] font-bold leading-none text-white" aria-label={`${confirmedOrderCount} confirmed orders awaiting fulfilment`}>{confirmedOrderCount}</span> : null}{item.exact ? null : <ChevronRightIcon className={cn('h-4 w-4 opacity-40', showConfirmedOrderCount ? '' : 'ml-auto')} aria-hidden="true" />}</NavLink></li>;
              })}
            </ul>
          </div>
        ))}
      </nav>
    </>
  );
}
