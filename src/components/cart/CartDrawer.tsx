import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  MinusIcon,
  PlusIcon,
  ShoppingBagIcon,
  Trash2Icon } from
'lucide-react';
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '../ui/sheet';
import { Button } from '../ui/button';
import { CheckoutForm } from './CheckoutForm';
import { StripePaymentStep } from './StripePaymentStep';
import { formatPrice } from '../../utils/currency';
import type { CheckoutResponse } from '../../types/order';
import { loadActiveCheckoutHandoff, saveCheckoutHandoff, type CheckoutHandoff } from '../../lib/checkoutHandoff';
import { getPaymentCapability } from '../../lib/paymentCapability';
import {
  selectItemCount,
  selectSubtotal,
  useCartStore } from
'../../hooks/useCartStore';

type Stage = 'basket' | 'checkout' | 'payment';

interface PlacedOrder {
  order: CheckoutResponse;
  checkoutAttemptId: string;
}

function hasUsableActiveHandoff(): CheckoutHandoff | null {
  const handoff = loadActiveCheckoutHandoff();
  if (!handoff) return null;
  try {
    return getPaymentCapability(handoff.checkoutAttemptId) ? handoff : null;
  } catch {
    return null;
  }
}

function checkoutResponseFromHandoff(handoff: CheckoutHandoff): CheckoutResponse {
  return {
    orderId: handoff.orderId,
    orderNumber: handoff.orderNumber,
    subtotal: handoff.subtotal,
    deliveryFee: handoff.deliveryFee,
    discountAmount: handoff.discountAmount,
    taxAmount: handoff.taxAmount,
    total: handoff.total,
    currency: handoff.currency,
    status: 'pending_payment',
    reservationExpiresAt: handoff.reservationExpiresAt
  };
}

export function CartDrawer() {
  const isOpen = useCartStore((state) => state.isOpen);
  const closeCart = useCartStore((state) => state.closeCart);
  const lines = useCartStore((state) => state.lines);
  const increment = useCartStore((state) => state.increment);
  const decrement = useCartStore((state) => state.decrement);
  const removeLine = useCartStore((state) => state.removeLine);
  const clear = useCartStore((state) => state.clear);
  const navigate = useNavigate();

  const [stage, setStage] = useState<Stage>('basket');
  const [placedOrder, setPlacedOrder] = useState<PlacedOrder | null>(null);
  const [activeHandoff, setActiveHandoff] = useState<CheckoutHandoff | null>(() => hasUsableActiveHandoff());
  const itemCount = selectItemCount({ lines });
  const subtotal = selectSubtotal({ lines });

  useEffect(() => {
    if (!isOpen) {
      const timer = window.setTimeout(() => setStage('basket'), 250);
      return () => window.clearTimeout(timer);
    }
    return undefined;
  }, [isOpen]);

  useEffect(() => {
    if (isOpen) setActiveHandoff(hasUsableActiveHandoff());
  }, [isOpen]);

  const continueExistingPayment = () => {
    if (!activeHandoff) return;
    setPlacedOrder({ order: checkoutResponseFromHandoff(activeHandoff), checkoutAttemptId: activeHandoff.checkoutAttemptId });
    setStage('payment');
  };

  const checkExistingPayment = () => {
    closeCart();
    navigate('/order-confirmation');
  };

  return (
    <Sheet open={isOpen} onOpenChange={(open) => open ? undefined : closeCart()}>
      <SheetContent aria-describedby="cart-description">
        <header className="border-b border-ink/10 bg-white px-5 py-4 pr-14">
          <SheetTitle className="font-display text-xl font-bold text-ink">
            {stage === 'payment' ? 'Secure payment' : 'Your basket'}
          </SheetTitle>
          <SheetDescription id="cart-description" className="mt-1 text-sm text-ink/60">
            {stage === 'payment' ?
            'Complete payment securely to submit your order for confirmation.' :
            `${itemCount} ${itemCount === 1 ? 'item' : 'items'} · delivered across the UK`}
          </SheetDescription>
        </header>

        {stage === 'payment' && placedOrder ?
        <StripePaymentStep order={placedOrder.order} checkoutAttemptId={placedOrder.checkoutAttemptId} /> :
        stage === 'checkout' ?
        <CheckoutForm
          subtotal={subtotal} lines={lines}
          onBack={() => setStage('basket')}
          onSuccess={(order: CheckoutResponse, checkoutAttemptId: string) => {
            saveCheckoutHandoff(order, checkoutAttemptId);
            setActiveHandoff(hasUsableActiveHandoff());
            setPlacedOrder({ order, checkoutAttemptId });
            setStage('payment');
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
              <div className="flex items-center justify-between border-t border-ink/10 pt-3 font-display text-lg font-bold text-ink">
                <span>Items subtotal</span>
                <span>{formatPrice(subtotal)}</span>
              </div>
              <p className="text-xs leading-relaxed text-ink/50">Delivery fee and final total are calculated securely after you provide your delivery address.</p>
              {activeHandoff ? <div className="space-y-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                <p className="font-semibold">You have an order awaiting payment.</p>
                <p className="text-amber-800">Continue the existing checkout or check its authoritative status before starting another order.</p>
                <Button size="lg" className="w-full" onClick={continueExistingPayment}>Continue payment</Button>
                <Button variant="outline" size="sm" className="w-full" onClick={checkExistingPayment}>Check payment status</Button>
              </div> : <>
                <Button size="lg" className="w-full" onClick={() => setStage('checkout')}>
                  Checkout
                </Button>
                <Button variant="ghost" size="sm" className="w-full" onClick={clear}>
                  Clear basket
                </Button>
              </>}
            </div>
          </>
        }
      </SheetContent>
    </Sheet>);

}
