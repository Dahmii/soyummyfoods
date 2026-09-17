import { useCallback, useEffect, useLayoutEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AlertCircleIcon, CheckCircle2Icon, Loader2Icon } from 'lucide-react';
import { Button } from '../components/ui/button';
import { getGuestOrderPaymentStatus } from '../repositories/checkoutRepository';
import { clearActiveCheckoutHandoff, loadCheckoutHandoff, markCheckoutHandoffConfirmed, type CheckoutHandoff } from '../lib/checkoutHandoff';
import { clearPaymentCapability, getPaymentCapability } from '../lib/paymentCapability';
import type { GuestOrderPaymentStatus } from '../types/order';
import { formatPrice } from '../utils/currency';
import { useCartStore } from '../hooks/useCartStore';

const pollIntervalMs = 1_500;
const pollTimeoutMs = 25_000;

type ConfirmationState = 'loading' | 'pending' | 'confirmed' | 'payment_failed' | 'cancelled' | 'unavailable' | 'no_handoff';

function removeStripeReturnParameters(): void {
  const url = new URL(window.location.href);
  let changed = false;
  for (const key of ['payment_intent', 'payment_intent_client_secret', 'redirect_status']) {
    if (url.searchParams.has(key)) {
      url.searchParams.delete(key);
      changed = true;
    }
  }
  if (changed) window.history.replaceState(window.history.state, '', `${url.pathname}${url.search}${url.hash}`);
}

function isConfirmed(status: GuestOrderPaymentStatus): boolean {
  return status.paymentStatus === 'succeeded'
    && status.orderStatus !== 'pending_payment'
    && status.orderStatus !== 'cancelled';
}

function isCancelled(status: GuestOrderPaymentStatus): boolean {
  return status.orderStatus === 'cancelled'
    || (status.terminal && status.paymentStatus !== 'succeeded');
}

function FinancialSummary({ status }: { status: GuestOrderPaymentStatus }) {
  return <dl className="mx-auto mt-6 w-full max-w-sm space-y-2 rounded-2xl border border-ink/10 bg-white p-4 text-left text-sm text-ink/70">
    <div className="flex justify-between gap-4"><dt>Items subtotal</dt><dd className="font-medium text-ink">{formatPrice(status.subtotal)}</dd></div>
    <div className="flex justify-between gap-4"><dt>Delivery fee</dt><dd className="font-medium text-ink">{formatPrice(status.deliveryFee)}</dd></div>
    {status.discountAmount !== 0 ? <div className="flex justify-between gap-4"><dt>Discount</dt><dd className="font-medium text-ink">−{formatPrice(status.discountAmount)}</dd></div> : null}
    {status.taxAmount !== 0 ? <div className="flex justify-between gap-4"><dt>Tax</dt><dd className="font-medium text-ink">{formatPrice(status.taxAmount)}</dd></div> : null}
    <div className="flex justify-between gap-4 border-t border-ink/10 pt-2 font-display text-base font-bold text-ink"><dt>Total</dt><dd>{formatPrice(status.total)}</dd></div>
  </dl>;
}

export function OrderConfirmationPage() {
  const [handoff] = useState<CheckoutHandoff | null>(() => loadCheckoutHandoff());
  const [state, setState] = useState<ConfirmationState>(() => handoff ? 'loading' : 'no_handoff');
  const [authoritativeStatus, setAuthoritativeStatus] = useState<GuestOrderPaymentStatus | null>(null);
  const [checkNumber, setCheckNumber] = useState(0);
  const clearCart = useCartStore((store) => store.clear);
  const openCart = useCartStore((store) => store.openCart);
  const navigate = useNavigate();

  useLayoutEffect(() => {
    removeStripeReturnParameters();
  }, []);

  const retry = useCallback(() => setCheckNumber((value) => value + 1), []);
  const returnToCart = () => {
    navigate('/menu');
    openCart();
  };

  useEffect(() => {
    if (!handoff) return;

    let active = true;
    let timer: number | undefined;
    const deadline = Date.now() + pollTimeoutMs;
    setState('loading');

    const check = async (): Promise<void> => {
      let capability: string | null;
      try {
        capability = getPaymentCapability(handoff.checkoutAttemptId);
      } catch {
        capability = null;
      }
      if (!capability) {
        if (active) setState('unavailable');
        return;
      }

      try {
        const status = await getGuestOrderPaymentStatus(handoff.orderId, capability);
        if (!active) return;
        setAuthoritativeStatus(status);

        if (isConfirmed(status)) {
          clearCart();
          markCheckoutHandoffConfirmed(handoff);
          setState('confirmed');
          return;
        }
        if (status.paymentStatus === 'payment_failed') {
          setState('payment_failed');
          return;
        }
        if (isCancelled(status)) {
          clearActiveCheckoutHandoff(handoff);
          clearPaymentCapability(handoff.checkoutAttemptId);
          setState('cancelled');
          return;
        }
      } catch {
        if (active) setState('unavailable');
        return;
      }

      if (!active) return;
      if (Date.now() >= deadline) {
        setState('pending');
      } else {
        setState('loading');
        timer = window.setTimeout(() => void check(), pollIntervalMs);
      }
    };

    void check();
    return () => {
      active = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [checkNumber, clearCart, handoff]);

  return <section className="mx-auto flex w-full max-w-xl flex-1 flex-col justify-center px-5 py-12 text-center">
    {state === 'no_handoff' ? <>
      <AlertCircleIcon className="mx-auto h-12 w-12 text-amber-600" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">Order confirmation unavailable</h1>
      <p className="mt-3 text-sm leading-relaxed text-ink/65">We could not find a payment session in this browser. Please return to the menu to begin a new order.</p>
      <Button asChild className="mt-6"><Link to="/menu">Return to menu</Link></Button>
    </> : null}

    {handoff && (state === 'loading' || state === 'pending') ? <>
      <Loader2Icon className="mx-auto h-12 w-12 animate-spin text-ink/60" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">Confirming your payment</h1>
      <p className="mt-3 text-sm leading-relaxed text-ink/65">Order <span className="font-semibold text-ink">{authoritativeStatus?.orderNumber ?? handoff.orderNumber}</span> is confirmed only after secure server-side verification.</p>
      {authoritativeStatus ? <FinancialSummary status={authoritativeStatus} /> : null}
      {state === 'pending' ? <div className="mt-6 space-y-3">
        <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">Confirmation is still pending. You can check again shortly.</p>
        <Button type="button" onClick={retry}>Check payment status</Button>
      </div> : null}
    </> : null}

    {handoff && state === 'confirmed' ? <>
      <CheckCircle2Icon className="mx-auto h-12 w-12 text-emerald-600" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">Payment confirmed</h1>
      <p className="mt-3 text-sm text-ink/65">Your payment has been verified and order <span className="font-semibold text-ink">{authoritativeStatus?.orderNumber ?? handoff.orderNumber}</span> is confirmed and sent for preparation.</p>
      {authoritativeStatus ? <><FinancialSummary status={authoritativeStatus} /><p className="mt-4 text-sm text-ink/65">Current order status: <span className="font-medium capitalize text-ink">{authoritativeStatus.orderStatus.replace(/_/g, ' ')}</span></p></> : null}
      <Button asChild className="mt-6"><Link to="/menu">Continue browsing</Link></Button>
    </> : null}

    {handoff && state === 'payment_failed' ? <>
      <AlertCircleIcon className="mx-auto h-12 w-12 text-amber-600" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">Payment was not completed</h1>
      <p className="mt-3 text-sm leading-relaxed text-ink/65">Your order is still awaiting payment while its reservation remains available.</p>
      {authoritativeStatus ? <FinancialSummary status={authoritativeStatus} /> : null}
      <div className="mt-6 flex flex-wrap justify-center gap-3"><Button type="button" onClick={retry}>Check again</Button><Button type="button" variant="outline" onClick={returnToCart}>Return to cart</Button></div>
    </> : null}

    {handoff && state === 'cancelled' ? <>
      <AlertCircleIcon className="mx-auto h-12 w-12 text-amber-600" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">This order is no longer available for payment</h1>
      <p className="mt-3 text-sm leading-relaxed text-ink/65">Please return to the menu to begin a new order.</p>
      {authoritativeStatus ? <FinancialSummary status={authoritativeStatus} /> : null}
      <Button type="button" className="mt-6" onClick={returnToCart}>Return to cart</Button>
    </> : null}

    {handoff && state === 'unavailable' ? <>
      <AlertCircleIcon className="mx-auto h-12 w-12 text-amber-600" />
      <h1 className="mt-4 font-display text-3xl font-bold text-ink">Payment status unavailable</h1>
      <p className="mt-3 text-sm leading-relaxed text-ink/65">We could not confirm this payment session. Please return to the menu to begin a new order.</p>
      {authoritativeStatus ? <FinancialSummary status={authoritativeStatus} /> : null}
      <div className="mt-6 flex flex-wrap justify-center gap-3"><Button type="button" onClick={retry}>Check again</Button><Button asChild variant="outline"><Link to="/menu">Return to menu</Link></Button></div>
    </> : null}
  </section>;
}
