import { create } from 'zustand';
import { effectivePrice, type MenuItem } from '../types/menu';

export interface CartLine {
  id: string;
  productId?: string;
  name: string;
  image: string;
  unitPrice: number;
  quantity: number;
}

interface CartState {
  lines: CartLine[];
  isOpen: boolean;
  lastAddedId: string | null;
  addItem: (item: MenuItem) => void;
  removeLine: (id: string) => void;
  increment: (id: string) => void;
  decrement: (id: string) => void;
  clear: () => void;
  openCart: () => void;
  closeCart: () => void;
  toggleCart: () => void;
}

export const useCartStore = create<CartState>((set) => ({
  lines: [],
  isOpen: false,
  lastAddedId: null,
  addItem: (item) =>
  set((state) => {
    const unitPrice = effectivePrice(item);
    if (unitPrice === null) return state;
    const existing = state.lines.find((line) => line.id === item.id);
    const lines = existing ?
    state.lines.map((line) =>
    line.id === item.id ? { ...line, quantity: line.quantity + 1 } : line
    ) :
    [
    ...state.lines,
    {
      id: item.id,
      productId: item.databaseId,
      name: item.name,
      image: item.image,
      unitPrice,
      quantity: 1
    }];

    return { lines, lastAddedId: item.id };
  }),
  removeLine: (id) =>
  set((state) => ({ lines: state.lines.filter((line) => line.id !== id) })),
  increment: (id) =>
  set((state) => ({
    lines: state.lines.map((line) =>
    line.id === id ? { ...line, quantity: line.quantity + 1 } : line
    )
  })),
  decrement: (id) =>
  set((state) => ({
    lines: state.lines.
    map((line) =>
    line.id === id ? { ...line, quantity: line.quantity - 1 } : line
    ).
    filter((line) => line.quantity > 0)
  })),
  clear: () => set({ lines: [], lastAddedId: null }),
  openCart: () => set({ isOpen: true }),
  closeCart: () => set({ isOpen: false }),
  toggleCart: () => set((state) => ({ isOpen: !state.isOpen }))
}));

export function selectItemCount(state: {lines: CartLine[];}): number {
  return state.lines.reduce((total, line) => total + line.quantity, 0);
}

export function selectSubtotal(state: {lines: CartLine[];}): number {
  return state.lines.reduce(
    (total, line) => total + line.unitPrice * line.quantity,
    0
  );
}
