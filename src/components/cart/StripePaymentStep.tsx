import React, { useEffect, useRef, useState } from 'react';
import { Elements, ExpressCheckoutElement, PaymentElement, useElements, useStripe } from '@stripe/react-stripe-js';
import { loadStripe } from '@stripe/stripe-js';
import { AlertCircleIcon, CheckCircle2Icon, Loader2Icon } from 'lucide-react';
import { Button } from '../ui/button';
import { CheckoutError, createStripePaymentIntent, getGuestOrderPaymentStatus } from '../../repositories/checkoutRepository';
import { clearPaymentCapability, getPaymentCapability } from '../../lib/paymentCapability';

const publishableKey = import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY?.trim();
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;
const statusPollIntervalMs = 1_500;
const statusPollTimeoutMs = 25_000;

interface StripePaymentStepProps {
  orderId: string;
  orderNumber: string;
  checkoutAttemptId: string;
}

function PaymentForm({ clientSecret, onSubmitted }: { clientSecret: string; onSubmitted: () => void }) {
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
      confirmParams: { return_url: `${window.location.origin}${window.location.pathname}` },
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
  const [confirmationState, setConfirmationState] = useState<'ready' | 'confirming' | 'confirmed' | 'cancelled' | 'payment_failed' | 'timed_out'>('ready');
  const pollingRef = useRef(false);

  useEffect(() => {
    const url = new URL(window.location.href);
    let changed = false;
    for (const key of ['payment_intent', 'payment_intent_client_secret', 'redirect_status']) {
      if (url.searchParams.has(key)) {
        url.searchParams.delete(key);
        changed = true;
      }
    }
    if (changed) {
      window.history.replaceState(window.history.state, '', `${url.pathname}${url.search}${url.hash}`);
    }
  }, []);

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

  useEffect(() => {
    if (confirmationState !== 'confirming') return;

    let active = true;
    let timer: number | undefined;
    const deadline = Date.now() + statusPollTimeoutMs;

    const poll = async () => {
      if (!active || pollingRef.current) return;

      let capability: string | null;
      try {
        capability = getPaymentCapability(checkoutAttemptId);
      } catch {
        capability = null;
      }
      if (!capability) {
        if (active) setConfirmationState('timed_out');
        return;
      }

      pollingRef.current = true;
      try {
        const status = await getGuestOrderPaymentStatus(orderId, capability);
        if (!active) return;

        if (status.paymentStatus === 'succeeded' && status.orderStatus !== 'pending_payment' && status.orderStatus !== 'cancelled') {
          clearPaymentCapability(checkoutAttemptId);
          setConfirmationState('confirmed');
          return;
        }
        if (status.terminal) {
          clearPaymentCapability(checkoutAttemptId);
          setConfirmationState('cancelled');
          return;
        }
        if (status.paymentStatus === 'payment_failed') {
          setConfirmationState('payment_failed');
          return;
        }
      } catch {
        // A transient status-read failure must never be shown as confirmation.
      } finally {
        pollingRef.current = false;
      }

      if (!active) return;
      if (Date.now() >= deadline) {
        setConfirmationState('timed_out');
      } else {
        timer = window.setTimeout(() => void poll(), statusPollIntervalMs);
      }
    };

    void poll();
    return () => {
      active = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [checkoutAttemptId, confirmationState, orderId]);

  return <div className="flex flex-1 flex-col gap-4 px-5 py-5">
    <div>
      <h3 className="font-display text-xl font-bold text-ink">Pay for order {orderNumber}</h3>
      <p className="mt-1 text-sm text-ink/60">Choose an available wallet or pay by card.</p>
    </div>
    {error ? <p role="alert" className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700"><AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />{error}</p> : null}
    {!error && !clientSecret ? <div className="flex items-center justify-center gap-2 py-8 text-sm text-ink/60"><Loader2Icon className="h-4 w-4 animate-spin" />Preparing secure payment…</div> : null}
    {!error && confirmationState === 'ready' && clientSecret && stripePromise ? <Elements stripe={stripePromise} options={{ clientSecret }}><PaymentForm clientSecret={clientSecret} onSubmitted={() => setConfirmationState('confirming')} /></Elements> : null}
    {!error && confirmationState === 'confirming' ? <div className="flex flex-col items-center gap-3 py-6 text-center">
      <Loader2Icon className="h-10 w-10 animate-spin text-ink/60" />
      <p className="font-semibold text-ink">Confirming your payment...</p>
      <p className="text-sm text-ink/60">Your order will be confirmed only after secure server-side verification.</p>
    </div> : null}
    {!error && confirmationState === 'confirmed' ? <div className="flex flex-col items-center gap-3 py-6 text-center">
      <CheckCircle2Icon className="h-12 w-12 text-emerald-600" />
      <p className="font-semibold text-ink">Payment confirmed.</p>
      <p className="text-sm text-ink/60">Your payment has been verified and order {orderNumber} is confirmed and sent for preparation.</p>
    </div> : null}
    {!error && confirmationState === 'cancelled' ? <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">This order is no longer available for payment.</p> : null}
    {!error && confirmationState === 'payment_failed' ? <div className="space-y-3 rounded-xl bg-amber-50 p-3 text-sm text-amber-800">
      <p>This payment attempt failed. Your order is still awaiting payment while its reservation remains valid.</p>
      <Button type="button" variant="outline" onClick={() => setConfirmationState('ready')}>Try payment again</Button>
    </div> : null}
    {!error && confirmationState === 'timed_out' ? <p role="status" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-800">Your payment was submitted, but confirmation is still pending. Please wait a moment before checking again.</p> : null}
  </div>;
}
