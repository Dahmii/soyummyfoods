import React from 'react';
import { Link, Outlet } from 'react-router-dom';
import { Button } from '../ui/button';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';

export function AdminLayout() {
  const { signOut } = useAdminAuth();

  return (
    <div className="min-h-screen bg-cream text-ink">
      <header className="border-b border-ink/10 bg-white">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 lg:px-8">
          <Link to="/admin" className="font-display text-xl font-bold text-ink">
            SoYummy Admin
          </Link>
          <Button size="sm" variant="outline" onClick={() => void signOut()}>
            Log out
          </Button>
        </div>
      </header>
      <main className="mx-auto max-w-7xl px-5 py-10 lg:px-8">
        <Outlet />
      </main>
    </div>
  );
}
