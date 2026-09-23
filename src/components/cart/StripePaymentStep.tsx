import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Elements, ExpressCheckoutElement, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { loadStripe } from '@stripe/stripe-js';
import { motion, useReducedMotion } from 'framer-motion';
import { AlertCircleIcon, CreditCardIcon, Loader2Icon } from 'lucide-react';
import { Button } from '../ui/button';
import { CheckoutError, createStripePaymentIntent } from '../../repositories/checkoutRepository';
import { getPaymentCapability } from '../../lib/paymentCapability';
import { readStripeBrowserConfiguration } from '../../lib/stripeMode';
import { useCartStore } from '../../hooks/useCartStore';
import type { CheckoutResponse } from '../../types/order';
import { formatPrice } from '../../utils/currency';

const stripeConfiguration = readStripeBrowserConfiguration();
const stripePromise = stripeConfiguration ? loadStripe(stripeConfiguration.publishableKey) : null;

interface StripePaymentStepProps {
  order: CheckoutResponse;
  checkoutAttemptId: string;
}

function PaymentForm({ clientSecret, total, onSubmitted }: { clientSecret: string; total: number; onSubmitted: () => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const reduceMotion = useReducedMotion();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isCardSelected, setIsCardSelected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submittingRef = useRef(false);
  const cardPaymentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isCardSelected) return;
    cardPaymentRef.current?.scrollIntoView({
      block: 'nearest',
      behavior: reduceMotion ? 'auto' : 'smooth'
    });
  }, [isCardSelected, reduceMotion]);

  async function confirmPayment(onWalletFailure?: () => void) {
    if (!stripe || !elements || submittingRef.current) return;
    submittingRef.current = true;
    setError(null);
    setIsSubmitting(true);
    const { error: submitError } = await elements.submit();
    if (submitError) {
      setError(submitError.message ?? 'Please check your payment details and try again.');
      onWalletFailure?.();
      setIsSubmitting(false);
      submittingRef.current = false;
      return;
    }
    const { error: confirmationError } = await stripe.confirmPayment({
      elements,
      clientSecret,
      confirmParams: { return_url: `${window.location.origin}/order-confirmation` },
      redirect: 'if_required'
    });
    if (confirmationError) {
      setError(confirmationError.message ?? 'Your payment could not be submitted. Please try again.');
      onWalletFailure?.();
    } else {
      onSubmitted();
    }
    setIsSubmitting(false);
    submittingRef.current = false;
  }

  return <div className="space-y-5">
    <section aria-labelledby="express-checkout-heading" className="space-y-3">
      <div>
        <h4 id="express-checkout-heading" className="font-display text-base font-bold text-ink">Express checkout</h4>
      </div>
      <ExpressCheckoutElement
        options={{
          layout: { maxColumns: 1, maxRows: 2, overflow: 'auto' },
          paymentMethods: { applePay: 'always', googlePay: 'always' }
        }}
        onConfirm={(event) => void confirmPayment(() => event.paymentFailed({ reason: 'fail' }))}
        onLoadError={() => undefined}
      />
    </section>
    <section aria-labelledby="card-payment-heading" className="space-y-3">
      <button
        type="button"
        aria-expanded={isCardSelected}
        aria-controls="stripe-card-payment"
        onClick={() => setIsCardSelected(true)}
        disabled={!stripe || !elements || isSubmitting}
        className="flex w-full items-center justify-between gap-4 rounded-2xl border border-ink/15 bg-white px-4 py-4 text-left shadow-sm transition-colors hover:border-brand-orange/55 hover:bg-brand-orange/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-orange focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-60"
      >
        <span className="flex min-w-0 items-center gap-3">
          <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-brand-orange/10 text-brand-orange"><CreditCardIcon className="h-5 w-5" aria-hidden="true" /></span>
          <span className="min-w-0">
            <span id="card-payment-heading" className="block font-display text-base font-bold text-ink">Pay with card</span>
            <span className="mt-0.5 block text-sm text-ink/60">Enter your card details securely with Stripe.</span>
          </span>
        </span>
        <span className="shrink-0 text-sm font-semibold text-brand-orange">{isCardSelected ? 'Selected' : 'Choose'}</span>
      </button>
      {isCardSelected ? <motion.div
        id="stripe-card-payment"
        ref={cardPaymentRef}
        initial={{ opacity: 0, y: reduceMotion ? 0 : -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: reduceMotion ? 0 : 0.18, ease: 'easeOut' }}
        className="space-y-4 rounded-2xl border border-ink/10 bg-cream/35 p-4 sm:p-5"
      >
        <PaymentElement options={{ layout: 'tabs' }} />
        <Button type="button" size="lg" className="w-full" disabled={!stripe || !elements || isSubmitting} onClick={() => void confirmPayment()}>
          {isSubmitting ? <><Loader2Icon className="h-4 w-4 animate-spin" />Submitting payment…</> : `Pay ${formatPrice(total)}`}
        </Button>
      </motion.div> : null}
    </section>
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
  </div>;
}

function PaymentSummary({ order }: { order: CheckoutResponse }) {
  return <dl className="space-y-2 rounded-2xl border border-ink/10 bg-white p-4 text-sm text-ink/70">
    <div className="flex justify-between gap-4"><dt>Items subtotal</dt><dd className="font-medium text-ink">{formatPrice(order.subtotal)}</dd></div>
    <div className="flex justify-between gap-4"><dt>Delivery fee</dt><dd className="font-medium text-ink">{formatPrice(order.deliveryFee)}</dd></div>
    {order.discountAmount !== 0 ? <div className="flex justify-between gap-4"><dt>Discount</dt><dd className="font-medium text-ink">−{formatPrice(order.discountAmount)}</dd></div> : null}
    {order.taxAmount !== 0 ? <div className="flex justify-between gap-4"><dt>Tax</dt><dd className="font-medium text-ink">{formatPrice(order.taxAmount)}</dd></div> : null}
    <div className="flex justify-between gap-4 border-t border-ink/10 pt-2 font-display text-lg font-bold text-ink"><dt>Total</dt><dd>{formatPrice(order.total)}</dd></div>
  </dl>;
}

export function StripePaymentStep({ order, checkoutAttemptId }: StripePaymentStepProps) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();
  const closeCart = useCartStore((state) => state.closeCart);

  useEffect(() => {
    if (!stripeConfiguration || !stripePromise) {
      setError('Online payment is temporarily unavailable.');
      return;
    }
    let capability: string | null;
    try {
      capability = getPaymentCapability(checkoutAttemptId);
    } catch {
      setError('Your payment session is no longer available. Please place your order again.');
      return;
    }
    if (!capability) {
      setError('Your payment session is no longer available. Please place your order again.');
      return;
    }
    let cancelled = false;
    void createStripePaymentIntent(order.orderId, capability)
      .then((payment) => {
        if (cancelled) return;
        if (payment.stripeMode !== stripeConfiguration.mode) {
          console.warn('Stripe payment mode mismatch between browser and payment service.');
          setError('Online payment is temporarily unavailable.');
          return;
        }
        setClientSecret(payment.clientSecret);
      })
      .catch((cause) => {
        if (!cancelled) setError(cause instanceof CheckoutError ? cause.message : 'Payment could not be started. Please try again.');
      });
    return () => { cancelled = true; };
  }, [checkoutAttemptId, order.orderId]);

  return <div className="flex flex-1 flex-col gap-4 px-5 py-5">
    <div>
      <h3 className="font-display text-xl font-bold text-ink">Pay for order {order.orderNumber}</h3>
      <p className="mt-1 text-sm text-ink/60">Choose an available wallet or pay by card.</p>
    </div>
    <PaymentSummary order={order} />
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
    {!error && !clientSecret ? <div className="flex items-center justify-center gap-2 py-8 text-sm text-ink/60"><Loader2Icon className="h-4 w-4 animate-spin" />Preparing secure payment…</div> : null}
    {!error && clientSecret && stripePromise ? <Elements stripe={stripePromise} options={{ clientSecret }}><PaymentForm clientSecret={clientSecret} total={order.total} onSubmitted={() => { closeCart(); navigate('/order-confirmation'); }} /></Elements> : null}
  </div>;
}
