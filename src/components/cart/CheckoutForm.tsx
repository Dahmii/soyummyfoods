import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Loader2Icon, AlertCircleIcon } from 'lucide-react';
import { Button } from '../ui/button';
import { Field, Input, Textarea } from '../ui/input';
import { formatPrice } from '../../utils/currency';
import type { CartLine } from '../../hooks/useCartStore';
import { CheckoutError, createGuestOrder } from '../../repositories/checkoutRepository';
import type { CheckoutResponse } from '../../types/order';

const checkoutSchema = z.object({
  fullName: z.string().min(2, 'Please enter your full name'),
  email: z.string().email('Enter a valid email address'),
  phone: z.
  string().
  min(7, 'Enter a valid phone number').
  regex(/^[0-9+()\s-]+$/, 'Phone can only contain digits and + ( ) -'),
  postcode: z.
  string().
  regex(
    /^[A-Za-z]{1,2}\d[A-Za-z\d]?\s?\d[A-Za-z]{2}$/,
    'Enter a valid UK postcode'
  ),
  address: z.string().min(6, 'Enter your delivery address'),
  notes: z.string().max(500, 'Keep notes under 500 characters').optional()
});

export type CheckoutValues = z.infer<typeof checkoutSchema>;

interface CheckoutFormProps {
  subtotal: number; lines: CartLine[];
  onSuccess: (order: CheckoutResponse) => void;
  onBack: () => void;
}

export function CheckoutForm({ subtotal, lines, onSuccess, onBack }: CheckoutFormProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [idempotencyKey, setIdempotencyKey] = useState(() => crypto.randomUUID());
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting }
  } = useForm<CheckoutValues>({
    resolver: zodResolver(checkoutSchema),
    defaultValues: {
      fullName: '',
      email: '',
      phone: '',
      postcode: '',
      address: '',
      notes: ''
    }
  });

  async function onSubmit(values: CheckoutValues) {
    setSubmitError(null);
    try {
      const checkoutLines = lines.map((line) => {
        if (!line.productId) throw new Error('Checkout is unavailable until the live menu has loaded.');
        return { productId: line.productId, quantity: line.quantity };
      });
      const order = await createGuestOrder({ lines: checkoutLines, customerName: values.fullName, email: values.email, phone: values.phone, deliveryAddress: values.address, postcode: values.postcode, customerNote: values.notes?.trim() || null, idempotencyKey });
      onSuccess(order);
    } catch (cause) {
      if (cause instanceof CheckoutError && cause.code === 'expired_idempotency_key') {
        setIdempotencyKey(crypto.randomUUID());
      }
      setSubmitError(cause instanceof Error ? cause.message : 'We could not place your order. Please try again.');
    }
  }

  return (
    <form
      onSubmit={handleSubmit(onSubmit)}
      noValidate
      className="flex h-full flex-col">
      
      <div className="flex-1 space-y-4 overflow-y-auto px-5 py-5 scrollbar-thin">
        <Field label="Full name" htmlFor="fullName" error={errors.fullName?.message}>
          <Input id="fullName" placeholder="Adebayo Bamson" {...register('fullName')} />
        </Field>
        <Field label="Email" htmlFor="email" error={errors.email?.message}>
          <Input
            id="email"
            type="email"
            placeholder="you@example.co.uk"
            {...register('email')} />
          
        </Field>
        <Field label="Phone" htmlFor="phone" error={errors.phone?.message}>
          <Input id="phone" type="tel" placeholder="+44 20 7946 0192" {...register('phone')} />
        </Field>
        <Field label="Postcode" htmlFor="postcode" error={errors.postcode?.message}>
          <Input id="postcode" placeholder="SE1 0AA" {...register('postcode')} />
        </Field>
        <Field
          label="Delivery address"
          htmlFor="address"
          error={errors.address?.message}>
          
          <Input id="address" placeholder="12 Southwark Street, London" {...register('address')} />
        </Field>
        <Field
          label="Kitchen notes (optional)"
          htmlFor="notes"
          error={errors.notes?.message}>
          
          <Textarea
            id="notes"
            placeholder="Extra scotch bonnet, no locust beans…"
            {...register('notes')} />
          
        </Field>

        <p className="text-xs leading-relaxed text-ink/50">
          Severe allergy? Tell us here and read our{' '}
          <Link
            to="/allergy"
            className="font-semibold text-brand-600 underline-offset-2 hover:underline">
            
            allergy advisory notice
          </Link>{' '}
          before ordering.
        </p>

        {submitError ?
        <p
          role="alert"
          className="flex items-start gap-2 rounded-xl bg-red-50 p-3 text-sm text-red-700">
          
            <AlertCircleIcon className="mt-0.5 h-4 w-4 shrink-0" />
            {submitError}
          </p> :
        null}
      </div>

      <div className="space-y-3 border-t border-ink/10 bg-white px-5 py-4">
        <div className="flex items-center justify-between font-display text-lg font-bold text-ink">
          <span>Items subtotal</span>
          <span>{formatPrice(subtotal)}</span>
        </div>
        <p className="text-xs leading-relaxed text-ink/50">Your delivery fee and final total will be calculated securely when you place the order.</p>
        <Button type="submit" size="lg" className="w-full" disabled={isSubmitting}>
          {isSubmitting ?
          <>
              <Loader2Icon className="h-4 w-4 animate-spin" /> Placing order…
            </> :

          'Place order'
          }
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          className="w-full"
          onClick={onBack}
          disabled={isSubmitting}>
          
          Back to basket
        </Button>
      </div>
    </form>);

}
