import React, { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Elements, ExpressCheckoutElement, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { loadStripe } from '@stripe/stripe-js';
import { AlertCircleIcon, Loader2Icon } from 'lucide-react';
import { Button } from '../ui/button';
import { CheckoutError, createStripePaymentIntent } from '../../repositories/checkoutRepository';
import { getPaymentCapability } from '../../lib/paymentCapability';
import { useCartStore } from '../../hooks/useCartStore';
import type { CheckoutResponse } from '../../types/order';
import { formatPrice } from '../../utils/currency';

const publishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY?.trim();
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;

interface StripePaymentStepProps {
  order: CheckoutResponse;
  checkoutAttemptId: string;
}

function PaymentForm({ clientSecret, total, onSubmitted }: { clientSecret: string; total: number; onSubmitted: () => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const submittingRef = useRef(false);

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

  return <div className="space-y-4">
    <ExpressCheckoutElement
      options={{ paymentMethods: { applePay: 'always', googlePay: 'always' } }}
      onConfirm={(event) => void confirmPayment(() => event.paymentFailed({ reason: 'fail' }))}
      onLoadError={() => undefined}
    />
    <div className="relative text-center text-xs text-ink/45 before:absolute before:inset-x-0 before:top-1/2 before:border-t before:border-ink/10"><span className="relative bg-white px-2">or pay by card</span></div>
    <PaymentElement options={{ layout: 'tabs' }} />
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
    <Button type="button" size="lg" className="w-full" disabled={!stripe || !elements || isSubmitting} onClick={() => void confirmPayment()}>
      {isSubmitting ? <><Loader2Icon className="h-4 w-4 animate-spin" />Submitting payment…</> : `Pay ${formatPrice(total)}`}
    </Button>
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
    if (!stripePromise) {
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
      .then((payment) => { if (!cancelled) setClientSecret(payment.clientSecret); })
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
