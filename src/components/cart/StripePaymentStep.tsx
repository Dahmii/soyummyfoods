import React, { useEffect, useRef, useState } from 'react';
import { Elements, ExpressCheckoutElement, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { loadStripe } from '@stripe/stripe-js';
import { AlertCircleIcon, CheckCircle2Icon, Loader2Icon } from 'lucide-react';
import { Button } from '../ui/button';
import { CheckoutError, createStripePaymentIntent } from '../../repositories/checkoutRepository';
import { getPaymentCapability } from '../../lib/paymentCapability';

const publishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY?.trim();
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;

interface StripePaymentStepProps {
  orderId: string;
  orderNumber: string;
  checkoutAttemptId: string;
}

function PaymentForm({ clientSecret }: { clientSecret: string }) {
  const stripe = useStripe();
  const elements = useElements();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
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
      confirmParams: { return_url: `${window.location.origin}${window.location.pathname}` },
      redirect: 'if_required'
    });
    if (confirmationError) {
      setError(confirmationError.message ?? 'Your payment could not be submitted. Please try again.');
      onWalletFailure?.();
    } else {
      setSubmitted(true);
    }
    setIsSubmitting(false);
    submittingRef.current = false;
  }

  if (submitted) {
    return <div className="flex flex-col items-center gap-3 py-6 text-center">
      <CheckCircle2Icon className="h-12 w-12 text-emerald-600" />
      <p className="font-semibold text-ink">Payment submitted.</p>
      <p className="text-sm text-ink/60">We’re confirming your payment. Your order is not confirmed until that verification is complete.</p>
    </div>;
  }

  return <div className="space-y-4">
    <ExpressCheckoutElement
      onConfirm={(event) => void confirmPayment(() => event.paymentFailed({ reason: 'fail' }))}
      onLoadError={() => undefined}
    />
    <div className="relative text-center text-xs text-ink/45 before:absolute before:inset-x-0 before:top-1/2 before:border-t before:border-ink/10"><span className="relative bg-white px-2">or pay by card</span></div>
    <PaymentElement options={{ layout: 'tabs' }} />
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
    <Button type="button" size="lg" className="w-full" disabled={!stripe || !elements || isSubmitting} onClick={() => void confirmPayment()}>
      {isSubmitting ? <><Loader2Icon className="h-4 w-4 animate-spin" />Submitting payment…</> : 'Pay securely'}
    </Button>
  </div>;
}

export function StripePaymentStep({ orderId, orderNumber, checkoutAttemptId }: StripePaymentStepProps) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

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
    void createStripePaymentIntent(orderId, capability)
      .then((payment) => { if (!cancelled) setClientSecret(payment.clientSecret); })
      .catch((cause) => {
        if (!cancelled) setError(cause instanceof CheckoutError ? cause.message : 'Payment could not be started. Please try again.');
      });
    return () => { cancelled = true; };
  }, [checkoutAttemptId, orderId]);

  return <div className="flex flex-1 flex-col gap-4 px-5 py-5">
    <div>
      <h3 className="font-display text-xl font-bold text-ink">Pay for order {orderNumber}</h3>
      <p className="mt-1 text-sm text-ink/60">Choose an available wallet or pay by card.</p>
    </div>
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
    {!error && !clientSecret ? <div className="flex items-center justify-center gap-2 py-8 text-sm text-ink/60"><Loader2Icon className="h-4 w-4 animate-spin" />Preparing secure payment…</div> : null}
    {clientSecret && stripePromise ? <Elements stripe={stripePromise} options={{ clientSecret }}><PaymentForm clientSecret={clientSecret} /></Elements> : null}
  </div>;
}
