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

export function App() {
  return (
    <BrowserRouter>
      <div className="flex min-h-screen w-full flex-col bg-cream">
        <Header />
        <main className="flex-1">
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/menu" element={<MenuPage />} />
            <Route path="/media" element={<MediaPage />} />
            <Route path="/blog" element={<BlogPage />} />
            <Route path="*" element={<HomePage />} />
          </Routes>
        </main>
        <Footer />
        <FloatingCart />
        <CartDrawer />
      </div>
    </BrowserRouter>);

}