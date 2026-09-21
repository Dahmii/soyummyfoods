import { BrowserRouter, Navigate, Routes, Route, useLocation } from 'react-router-dom';
import { Header } from './components/layout/Header';
import { Footer } from './components/layout/Footer';
import { FloatingCart } from './components/cart/FloatingCart';
import { CartDrawer } from './components/cart/CartDrawer';
import { HomePage } from './pages/Home';
import { MenuPage } from './pages/Menu';
import { MediaPage } from './pages/Media';
import { BlogPage } from './pages/Blog';
import { AllergyPage } from './pages/Allergy';
import { OrderConfirmationPage } from './pages/OrderConfirmation';
import { NotFoundPage } from './pages/NotFound';
import { RequireAdmin } from './components/admin/RequireAdmin';
import { AdminLayout } from './components/admin/AdminLayout';
import { AdminLoginPage } from './pages/admin/Login';
import { AdminDashboardPage } from './pages/admin/Dashboard';
import { AdminCategoriesPage } from './pages/admin/CatalogCategories';
import { AdminProductsPage } from './pages/admin/CatalogProducts';
import { AdminProductEditorPage } from './pages/admin/CatalogProductEditor';
import { AdminBusinessSettingsPage } from './pages/admin/BusinessSettings';
import { AdminDeliveryZonesPage } from './pages/admin/DeliveryZones';
import { AdminDeliveryZoneEditorPage } from './pages/admin/DeliveryZoneEditor';
import { AdminInventoryListPage } from './pages/admin/InventoryList';
import { AdminInventoryDetailPage } from './pages/admin/InventoryDetail';
import { AdminOrdersPage } from './pages/admin/Orders';
import { AdminOrderDetailPage } from './pages/admin/OrderDetail';
import { AdminPaymentReconciliationPage } from './pages/admin/PaymentReconciliation';

export function App() {
  return (
    <BrowserRouter>
      <AppContent />
    </BrowserRouter>);
}

function AppContent() {
  const { pathname } = useLocation();
  const isAdminRoute = pathname === '/admin' || pathname.startsWith('/admin/');

  return (
    <div className={isAdminRoute ? 'min-h-screen bg-[#f7f5f1]' : 'flex min-h-screen w-full flex-col bg-cream'}>
      {isAdminRoute ? null : <Header />}
      <main className={isAdminRoute ? 'min-h-screen' : 'flex-1'}>
        <Routes>
            <Route path="/admin/login" element={<AdminLoginPage />} />
            <Route path="/admin" element={<RequireAdmin />}>
              <Route element={<AdminLayout />}>
                <Route index element={<AdminDashboardPage />} />
                <Route path="catalog/categories" element={<AdminCategoriesPage />} />
                <Route path="catalog/products" element={<AdminProductsPage />} />
                <Route path="catalog/products/new" element={<AdminProductEditorPage />} />
                <Route path="catalog/products/:productId/edit" element={<AdminProductEditorPage />} />
                <Route path="settings/business" element={<AdminBusinessSettingsPage />} />
                <Route path="delivery-zones" element={<AdminDeliveryZonesPage />} />
                <Route path="delivery-zones/new" element={<AdminDeliveryZoneEditorPage />} />
                <Route path="delivery-zones/:zoneId/edit" element={<AdminDeliveryZoneEditorPage />} />
                <Route path="inventory" element={<AdminInventoryListPage />} />
                <Route path="inventory/:productId" element={<AdminInventoryDetailPage />} />
                <Route path="orders" element={<AdminOrdersPage />} />
                <Route path="orders/:orderId" element={<AdminOrderDetailPage />} />
                <Route path="payments/reconciliation" element={<AdminPaymentReconciliationPage />} />
                <Route path="*" element={<Navigate to="/admin" replace />} />
              </Route>
            </Route>
            <Route path="/" element={<HomePage />} />
            <Route path="/menu" element={<MenuPage />} />
            <Route path="/media" element={<MediaPage />} />
            <Route path="/blog" element={<BlogPage />} />
            <Route path="/allergy" element={<AllergyPage />} />
            <Route path="/order-confirmation" element={<OrderConfirmationPage />} />
            <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </main>
      {isAdminRoute ? null : <Footer />}
      {isAdminRoute ? null : <FloatingCart />}
      {isAdminRoute ? null : <CartDrawer />}
    </div>
  );
}
