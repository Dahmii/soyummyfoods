import React, { useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Button } from '../../components/ui/button';
import { Input } from '../../components/ui/input';
import { useAdminAuth } from '../../features/admin/AdminAuthContext';

interface LocationState {
  from?: string;
}

export function AdminLoginPage() {
  const { isAdmin, isConfigured, isLoading, session, signIn, signOut } = useAdminAuth();
  const location = useLocation();
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const from = (location.state as LocationState | null)?.from || '/admin';

  if (!isLoading && isAdmin) return <Navigate to={from} replace />;

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);
    const signInError = await signIn(email, password);
    setIsSubmitting(false);

    if (signInError) {
      setError(signInError);
      return;
    }

    navigate(from, { replace: true });
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-cream px-5 py-10">
      <section className="w-full max-w-md rounded-2xl border border-ink/10 bg-white p-6 shadow-card sm:p-8">
        <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-500">SoYummy Foods</p>
        <h1 className="mt-2 font-display text-3xl font-bold text-ink">Admin sign in</h1>
        <p className="mt-2 text-sm leading-relaxed text-ink/60">
          This area is restricted to authorised SoYummy staff.
        </p>

        {!isConfigured ?
        <p role="alert" className="mt-6 rounded-xl bg-red-50 p-3 text-sm text-red-700">
            Admin authentication is not configured in this environment.
          </p> :
        session && !isLoading ?
        <div className="mt-6 space-y-3">
            <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-700">
              This account is not authorised to access the admin area.
            </p>
            <Button variant="outline" className="w-full" onClick={() => void signOut()}>
              Sign out
            </Button>
          </div> :
        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <div>
              <label htmlFor="admin-email" className="text-sm font-medium text-ink">Email</label>
              <Input
                id="admin-email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required />
            </div>
            <div>
              <label htmlFor="admin-password" className="text-sm font-medium text-ink">Password</label>
              <Input
                id="admin-password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                required />
            </div>
            {error ? <p role="alert" className="text-sm text-red-700">{error}</p> : null}
            <Button type="submit" className="w-full" disabled={isSubmitting || isLoading}>
              {isSubmitting ? 'Signing in…' : 'Sign in'}
            </Button>
          </form>
        }
      </section>
    </main>
  );
}
