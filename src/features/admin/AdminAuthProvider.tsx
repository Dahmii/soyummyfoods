import React, {
  useCallback,
  useEffect,
  useMemo,
  useState
} from 'react';
import type { Session } from '@supabase/supabase-js';
import { getSupabaseClient, isSupabaseConfigured } from '../../lib/supabase';
import type { AppRole } from '../../types/admin';
import { AdminAuthContext, type AdminAuthContextValue } from './AdminAuthContext';

function toRoles(data: Array<{ role: AppRole }> | null): AppRole[] {
  return data?.map((entry) => entry.role) ?? [];
}

export function AdminAuthProvider({ children }: {children: React.ReactNode;}) {
  const [session, setSession] = useState<Session | null>(null);
  const [roles, setRoles] = useState<AppRole[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const isConfigured = isSupabaseConfigured();

  const loadAccess = useCallback(async (nextSession: Session | null) => {
    setSession(nextSession);

    if (!nextSession) {
      setRoles([]);
      setIsLoading(false);
      return;
    }

    const { data, error } = await getSupabaseClient().
    from('user_roles').
    select('role').
    eq('user_id', nextSession.user.id);

    setRoles(error ? [] : toRoles(data as Array<{role: AppRole;}> | null));
    setIsLoading(false);
  }, []);

  useEffect(() => {
    if (!isConfigured) {
      setIsLoading(false);
      return undefined;
    }

    const supabase = getSupabaseClient();
    void supabase.auth.getSession().then(({ data }) => loadAccess(data.session));

    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      window.setTimeout(() => void loadAccess(nextSession), 0);
    });

    return () => listener.subscription.unsubscribe();
  }, [isConfigured, loadAccess]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!isConfigured) return 'Admin authentication is not configured in this environment.';

    const { error } = await getSupabaseClient().auth.signInWithPassword({ email, password });
    return error?.message ?? null;
  }, [isConfigured]);

  const signOut = useCallback(async () => {
    if (isConfigured) await getSupabaseClient().auth.signOut();
    setSession(null);
    setRoles([]);
  }, [isConfigured]);

  const value = useMemo<AdminAuthContextValue>(() => ({
    session,
    roles,
    isLoading,
    isConfigured,
    isAdmin: roles.length > 0,
    signIn,
    signOut
  }), [isConfigured, isLoading, roles, session, signIn, signOut]);

  return <AdminAuthContext.Provider value={value}>{children}</AdminAuthContext.Provider>;
}
