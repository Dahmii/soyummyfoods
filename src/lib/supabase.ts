import { createClient, type SupabaseClient } from '@supabase/supabase-js';

interface PublicSupabaseConfig {
  url: string;
  publishableKey: string;
}

let client: SupabaseClient | null = null;

function readPublicConfig(): PublicSupabaseConfig | null {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!url && !publishableKey) return null;
  if (!url || !publishableKey) {
    throw new Error(
      'Supabase is not configured correctly. Set both VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY.'
    );
  }

  try {
    new URL(url);
  } catch {
    throw new Error('VITE_SUPABASE_URL must be a valid URL.');
  }

  return { url, publishableKey };
}

export function isSupabaseConfigured(): boolean {
  return readPublicConfig() !== null;
}

export function getSupabaseClient(): SupabaseClient {
  const config = readPublicConfig();
  if (!config) {
    throw new Error('Supabase is not configured for this environment.');
  }

  if (!client) {
    client = createClient(config.url, config.publishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });
  }

  return client;
}
