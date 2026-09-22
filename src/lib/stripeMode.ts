export type StripeMode = 'test' | 'live';

export interface StripeBrowserConfiguration {
  mode: StripeMode;
  publishableKey: string;
}

function isStripeMode(value: string | undefined): value is StripeMode {
  return value === 'test' || value === 'live';
}

export function readStripeBrowserConfiguration(): StripeBrowserConfiguration | null {
  const mode = import.meta.env.VITE_STRIPE_MODE;
  const publishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY;

  if (!isStripeMode(mode) || !publishableKey) return null;

  const requiredPrefix = mode === 'test' ? 'pk_test_' : 'pk_live_';
  if (!publishableKey.startsWith(requiredPrefix)) return null;

  return { mode, publishableKey };
}
