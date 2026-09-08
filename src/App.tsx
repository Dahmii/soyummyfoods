import React from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Header } from './components/layout/Header';
import { Footer } from './components/layout/Footer';
import { FloatingCart } from './components/cart/FloatingCart';
import { CartDrawer } from './components/cart/CartDrawer';
import { HomePage } from './pages/Home';
import { MenuPage } from './pages/Menu';
import { MediaPage } from './pages/Media';
import { BlogPage } from './pages/Blog';
import { AllergyPage } from './pages/Allergy';
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

export function App() {
  return (
    <BrowserRouter>
      <div className="flex min-h-screen w-full flex-col bg-cream">
        <Header />
        <main className="flex-1">
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
              </Route>
            </Route>
            <Route path="/" element={<HomePage />} />
            <Route path="/menu" element={<MenuPage />} />
            <Route path="/media" element={<MediaPage />} />
            <Route path="/blog" element={<BlogPage />} />
            <Route path="/allergy" element={<AllergyPage />} />
            <Route path="*" element={<HomePage />} />
          </Routes>
        </main>
        <Footer />
        <FloatingCart />
        <CartDrawer />
      </div>
    </BrowserRouter>);

}
