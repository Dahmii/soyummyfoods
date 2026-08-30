import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  MinusIcon,
  PlusIcon,
  ShoppingBagIcon,
  Trash2Icon,
  CheckCircle2Icon,
  TruckIcon,
  MessageCircleIcon } from
'lucide-react';
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '../ui/sheet';
import { Button } from '../ui/button';
import { CheckoutForm, type CheckoutValues } from './CheckoutForm';
import { formatPrice } from '../../utils/currency';
import { buildOrderMessage, openWhatsApp } from '../../utils/whatsapp';
import type { CartLine } from '../../hooks/useCartStore';
import {
  DELIVERY_FEE,
  FREE_DELIVERY_THRESHOLD,
  selectItemCount,
  selectSubtotal,
  useCartStore } from
'../../hooks/useCartStore';

type Stage = 'basket' | 'checkout' | 'confirmed';

interface PlacedOrder {
  lines: CartLine[];
  subtotal: number;
  delivery: number;
  total: number;
  customer: CheckoutValues;
}

export function CartDrawer() {
  const isOpen = useCartStore((state) => state.isOpen);
  const closeCart = useCartStore((state) => state.closeCart);
  const lines = useCartStore((state) => state.lines);
  const increment = useCartStore((state) => state.increment);
  const decrement = useCartStore((state) => state.decrement);
  const removeLine = useCartStore((state) => state.removeLine);
  const clear = useCartStore((state) => state.clear);

  const [stage, setStage] = useState<Stage>('basket');
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const itemCount = selectItemCount({ lines });
  const subtotal = selectSubtotal({ lines });
  const delivery = subtotal >= FREE_DELIVERY_THRESHOLD || subtotal === 0 ? 0 : DELIVERY_FEE;
  const total = subtotal + delivery;

  useEffect(() => {
    if (!isOpen) {
      const timer = window.setTimeout(() => setStage('basket'), 250);
      return () => window.clearTimeout(timer);
    }
    return undefined;
  }, [isOpen]);

  return (
    <Sheet open={isOpen} onOpenChange={(open) => open ? undefined : closeCart()}>
      <SheetContent aria-describedby="cart-description">
        <header className="border-b border-ink/10 bg-white px-5 py-4 pr-14">
          <SheetTitle className="font-display text-xl font-bold text-ink">
            {stage === 'confirmed' ? 'Order confirmed' : 'Your basket'}
          </SheetTitle>
          <SheetDescription id="cart-description" className="mt-1 text-sm text-ink/60">
            {stage === 'confirmed' ?
            'Our kitchen has started prepping your order.' :
            `${itemCount} ${itemCount === 1 ? 'item' : 'items'} · delivered across the UK`}
          </SheetDescription>
        </header>

        {stage === 'confirmed' ?
        <div className="flex flex-1 flex-col items-center justify-center gap-4 px-8 text-center">
            <CheckCircle2Icon className="h-14 w-14 text-emerald-600" />
            <h3 className="font-display text-2xl font-bold text-ink">Thank you!</h3>
            <p className="text-sm leading-relaxed text-ink/60">
              We've sent a confirmation email with your delivery window. Send the order
              to our WhatsApp to settle payment or adjust your delivery address.
            </p>
            {placedOrder ?
          <Button
            size="lg"
            className="mt-2 w-full bg-[#25D366] hover:bg-[#1EBE57]"
            onClick={() =>
            openWhatsApp(
              buildOrderMessage({
                lines: placedOrder.lines,
                subtotal: placedOrder.subtotal,
                delivery: placedOrder.delivery,
                total: placedOrder.total,
                customer: placedOrder.customer
              })
            )
            }>
            
                <MessageCircleIcon className="h-4 w-4" /> Finalise on WhatsApp
              </Button> :
          null}
            <Button onClick={closeCart} variant="ghost" size="sm">
              Continue browsing
            </Button>
          </div> :
        stage === 'checkout' ?
        <CheckoutForm
          total={total}
          onBack={() => setStage('basket')}
          onSuccess={(customer) => {
            setPlacedOrder({ lines, subtotal, delivery, total, customer });
            clear();
            setStage('confirmed');
          }} /> :

        lines.length === 0 ?
        <div className="flex flex-1 flex-col items-center justify-center gap-4 px-8 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-brand-50">
              <ShoppingBagIcon className="h-7 w-7 text-brand-500" />
            </div>
            <h3 className="font-display text-xl font-bold text-ink">
              Your basket is empty
            </h3>
            <p className="text-sm text-ink/60">
              Browse our slow-cooked classics and add your favourites.
            </p>
            <Button asChild onClick={closeCart}>
              <Link to="/menu">Explore the menu</Link>
            </Button>
          </div> :

        <>
            <ul className="flex-1 space-y-3 overflow-y-auto px-5 py-5 scrollbar-thin">
              {lines.map((line) =>
            <li
              key={line.id}
              className="flex gap-3 rounded-2xl border border-ink/10 bg-white p-3">
              
                  <img
                src={line.image}
                alt=""
                className="h-20 w-20 shrink-0 rounded-xl object-cover" />
              
                  <div className="flex min-w-0 flex-1 flex-col">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="truncate text-sm font-semibold text-ink">
                        {line.name}
                      </h3>
                      <button
                    type="button"
                    onClick={() => removeLine(line.id)}
                    aria-label={`Remove ${line.name} from basket`}
                    className="rounded-full p-1 text-ink/40 transition-colors hover:bg-red-50 hover:text-red-600">
                    
                        <Trash2Icon className="h-4 w-4" />
                      </button>
                    </div>
                    <p className="mt-0.5 text-xs text-ink/50">
                      {formatPrice(line.unitPrice)} each
                    </p>
                    <div className="mt-auto flex items-center justify-between pt-2">
                      <div className="flex items-center gap-1 rounded-full border border-ink/10 p-0.5">
                        <button
                      type="button"
                      onClick={() => decrement(line.id)}
                      aria-label={`Decrease quantity of ${line.name}`}
                      className="flex h-7 w-7 items-center justify-center rounded-full text-ink transition-colors hover:bg-ink/5">
                      
                          <MinusIcon className="h-3.5 w-3.5" />
                        </button>
                        <span
                      aria-live="polite"
                      className="w-6 text-center text-sm font-semibold text-ink">
                      
                          {line.quantity}
                        </span>
                        <button
                      type="button"
                      onClick={() => increment(line.id)}
                      aria-label={`Increase quantity of ${line.name}`}
                      className="flex h-7 w-7 items-center justify-center rounded-full text-ink transition-colors hover:bg-ink/5">
                      
                          <PlusIcon className="h-3.5 w-3.5" />
                        </button>
                      </div>
                      <span className="font-display text-base font-bold text-ink">
                        {formatPrice(line.unitPrice * line.quantity)}
                      </span>
                    </div>
                  </div>
                </li>
            )}
            </ul>

            <div className="space-y-3 border-t border-ink/10 bg-white px-5 py-4">
              <div className="flex items-center justify-between text-sm text-ink/60">
                <span>Subtotal</span>
                <span className="font-medium text-ink">{formatPrice(subtotal)}</span>
              </div>
              <div className="flex items-center justify-between text-sm text-ink/60">
                <span className="inline-flex items-center gap-1.5">
                  <TruckIcon className="h-4 w-4 text-brand-500" /> Delivery
                </span>
                <span className="font-medium text-ink">
                  {delivery === 0 ? 'Free' : formatPrice(delivery)}
                </span>
              </div>
              {subtotal < FREE_DELIVERY_THRESHOLD ?
            <p className="rounded-xl bg-brand-50 px-3 py-2 text-xs font-medium text-brand-700">
                  Spend {formatPrice(FREE_DELIVERY_THRESHOLD - subtotal)} more for free
                  UK delivery.
                </p> :
            null}
              <div className="flex items-center justify-between border-t border-ink/10 pt-3 font-display text-lg font-bold text-ink">
                <span>Total</span>
                <span>{formatPrice(total)}</span>
              </div>
              <Button size="lg" className="w-full" onClick={() => setStage('checkout')}>
                Checkout
              </Button>
              <Button
              size="lg"
              className="w-full bg-[#25D366] hover:bg-[#1EBE57]"
              onClick={() =>
              openWhatsApp(buildOrderMessage({ lines, subtotal, delivery, total }))
              }>
              
                <MessageCircleIcon className="h-4 w-4" /> Order on WhatsApp
              </Button>
              <p className="text-center text-xs leading-relaxed text-ink/50">
                Sending on WhatsApp lets you confirm payment and delivery address
                directly with our team.
              </p>
              <Button variant="ghost" size="sm" className="w-full" onClick={clear}>
                Clear basket
              </Button>
            </div>
          </>
        }
      </SheetContent>
    </Sheet>);

}