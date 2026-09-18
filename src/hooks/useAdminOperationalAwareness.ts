import { useCallback, useEffect, useRef, useState } from 'react';
import {
  countAdminConfirmedOrders,
  listAdminActionableOrders
} from '../repositories/adminOrderRepository';
import type { AdminActionableOrder } from '../types/adminOrders';

const REFRESH_INTERVAL_MS = 15_000;

export interface AdminOperationalAwareness {
  actionableOrders: AdminActionableOrder[];
  confirmedOrderCount: number;
  error: string | null;
  isLoading: boolean;
  refresh: () => Promise<void>;
}

export function useAdminOperationalAwareness(): AdminOperationalAwareness {
  const [actionableOrders, setActionableOrders] = useState<AdminActionableOrder[]>([]);
  const [confirmedOrderCount, setConfirmedOrderCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const isMountedRef = useRef(true);
  const refreshInFlightRef = useRef(false);

  const refresh = useCallback(async (allowWhenHidden = false) => {
    if (refreshInFlightRef.current || (!allowWhenHidden && document.visibilityState === 'hidden')) return;

    refreshInFlightRef.current = true;
    try {
      const [nextOrders, nextConfirmedCount] = await Promise.all([
        listAdminActionableOrders(),
        countAdminConfirmedOrders()
      ]);
      if (!isMountedRef.current) return;

      setActionableOrders(nextOrders);
      setConfirmedOrderCount(nextConfirmedCount);
      setError(null);
    } catch (refreshError) {
      if (isMountedRef.current) {
        setError(refreshError instanceof Error ? refreshError.message : 'Unable to refresh orders needing attention.');
      }
    } finally {
      refreshInFlightRef.current = false;
      if (isMountedRef.current) setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    isMountedRef.current = true;
    void refresh(true);

    const refreshWhenVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', refreshWhenVisible);
    window.addEventListener('focus', refreshWhenVisible);
    const intervalId = window.setInterval(() => void refresh(), REFRESH_INTERVAL_MS);

    return () => {
      isMountedRef.current = false;
      window.clearInterval(intervalId);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      window.removeEventListener('focus', refreshWhenVisible);
    };
  }, [refresh]);

  return {
    actionableOrders,
    confirmedOrderCount,
    error,
    isLoading,
    refresh: () => refresh(true)
  };
}
