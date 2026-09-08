import { useCallback, useEffect, useState } from 'react';
import { fetchMenu } from '../data/menu';
import type { MenuCategoryOption, MenuItem } from '../types/menu';

interface UseMenuResult {
  items: MenuItem[];
  categories: MenuCategoryOption[];
  isLoading: boolean;
  error: string | null;
  retry: () => void;
}

export function useMenu(): UseMenuResult {
  const [items, setItems] = useState<MenuItem[]>([]);
  const [categories, setCategories] = useState<MenuCategoryOption[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setIsLoading(true);
    setError(null);

    fetchMenu(controller.signal).
    then((data) => {
      setItems(data.items);
      setCategories(data.categories);
      setIsLoading(false);
    }).
    catch((cause: unknown) => {
      if (cause instanceof DOMException && cause.name === 'AbortError') return;
      setError(
        cause instanceof Error ?
        cause.message :
        'Something went wrong loading the menu.'
      );
      setIsLoading(false);
    });

    return () => controller.abort();
  }, [attempt]);

  const retry = useCallback(() => setAttempt((value) => value + 1), []);

  return { items, categories, isLoading, error, retry };
}
