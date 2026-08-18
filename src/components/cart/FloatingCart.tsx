import React from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { ShoppingCartIcon } from 'lucide-react';
import { formatPrice } from '../../utils/currency';
import {
  selectItemCount,
  selectSubtotal,
  useCartStore } from
'../../hooks/useCartStore';

export function FloatingCart() {
  const lines = useCartStore((state) => state.lines);
  const isOpen = useCartStore((state) => state.isOpen);
  const openCart = useCartStore((state) => state.openCart);

  const itemCount = selectItemCount({ lines });
  const subtotal = selectSubtotal({ lines });
  const visible = itemCount > 0 && !isOpen;

  return (
    <AnimatePresence>
      {visible ?
      <motion.div
        initial={{ opacity: 0, y: 24, scale: 0.96 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 24, scale: 0.96 }}
        transition={{ type: 'spring', stiffness: 340, damping: 28 }}
        className="fixed bottom-5 right-5 z-40 sm:bottom-7 sm:right-7">
        
          <button
          type="button"
          onClick={openCart}
          aria-label={`Open basket, ${itemCount} items, total ${formatPrice(subtotal)}`}
          className="flex items-center gap-3 rounded-full bg-brand-500 py-3 pl-4 pr-5 text-white shadow-lift transition-colors hover:bg-brand-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 active:scale-[0.98]">
          
            <span className="relative flex h-9 w-9 items-center justify-center rounded-full bg-white/20">
              <ShoppingCartIcon className="h-5 w-5" />
              <motion.span
              key={itemCount}
              initial={{ scale: 0.6 }}
              animate={{ scale: 1 }}
              transition={{ type: 'spring', stiffness: 500, damping: 20 }}
              className="absolute -right-1.5 -top-1.5 flex h-5 min-w-[1.25rem] items-center justify-center rounded-full bg-ink px-1 text-[11px] font-bold text-white">
              
                {itemCount}
              </motion.span>
            </span>
            <span className="flex flex-col items-start leading-tight">
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-white/80">
                Cart ({itemCount})
              </span>
              <span className="font-display text-base font-bold">
                {formatPrice(subtotal)}
              </span>
            </span>
          </button>
        </motion.div> :
      null}
    </AnimatePresence>);

}