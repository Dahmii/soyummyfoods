import React from 'react';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';

export function AdminDashboardPage() {
  const { roles, session } = useAdminAuth();

  return (
    <section>
      <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-500">Administration</p>
      <h1 className="mt-2 font-display text-3xl font-bold text-ink">Welcome to SoYummy Admin</h1>
      <p className="mt-3 max-w-2xl text-sm leading-relaxed text-ink/60">
        You are signed in as {session?.user.email ?? 'an authorised administrator'}.
      </p>
      <p className="mt-5 text-sm font-medium text-ink/70">
        Role{roles.length === 1 ? '' : 's'}: {roles.join(', ')}
      </p>
    </section>
  );
}
