import React from 'react';
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';

export function RequireAdmin() {
  const { isAdmin, isLoading, session } = useAdminAuth();
  const location = useLocation();

  if (isLoading) {
    return <div className="min-h-screen bg-cream" aria-busy="true" />;
  }

  if (!session || !isAdmin) {
    return <Navigate to="/admin/login" replace state={{ from: location.pathname }} />;
  }

  return <Outlet />;
}
