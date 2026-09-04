import { createContext, useContext } from 'react';
import type { Session } from '@supabase/supabase-js';
import type { AppRole } from '../../types/admin';

export interface AdminAuthContextValue {
  session: Session | null;
  roles: AppRole[];
  isLoading: boolean;
  isConfigured: boolean;
  isAdmin: boolean;
  signIn: (email: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;
}

export const AdminAuthContext = createContext<AdminAuthContextValue | null>(null);

export function useAdminAuth(): AdminAuthContextValue {
  const context = useContext(AdminAuthContext);
  if (!context) throw new Error('useAdminAuth must be used within AdminAuthProvider.');
  return context;
}
