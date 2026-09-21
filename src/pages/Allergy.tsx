import React from 'react';
import { Link } from 'react-router-dom';
import { AlertTriangleIcon, MessageCircleIcon } from 'lucide-react';
import { Button } from '../components/ui/button';
import {
  buildAllergyEnquiryMessage,
  openWhatsApp } from
'../utils/whatsapp';

const ALLERGENS = [
'Gluten',
'Fish',
'Crustaceans',
'Soybeans',
'Nuts',
'Seeds',
'Eggs'];


export function AllergyPage() {
  return (
    <div className="w-full bg-white">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <span className="inline-flex items-center gap-2 rounded-full bg-brand-500 px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em] text-white">
            <AlertTriangleIcon className="h-3.5 w-3.5" /> Please read before ordering
          </span>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">
            Allergy Advisory Notice
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
            Your safety matters to us as much as flavour does. Here is exactly how our
            kitchen operates and what we can and cannot guarantee.
          </p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-8 px-5 py-14 lg:grid-cols-[minmax(0,1fr)_20rem] lg:px-8 lg:py-16">
        <article className="space-y-8">
          <section
            aria-labelledby="cross-contamination"
            className="rounded-2xl border-l-4 border-brand-500 bg-brand-50 p-6 sm:p-8">
            
            <h2
              id="cross-contamination"
              className="font-display text-2xl font-bold text-ink">
              
              Cross-Contamination Warning
            </h2>
            <p className="mt-4 text-base leading-relaxed text-ink/75">
              All dishes are prepared in a kitchen environment that handles gluten,
              fish, crustaceans, soybeans, nuts, seeds, and eggs. We cannot guarantee
              that any item is 100% free of cross-contamination. Customers with severe
              allergies should notify the kitchen prior to ordering to discuss specific
              dietary requirements.
            </p>
          </section>

          <section aria-labelledby="handled-allergens">
            <h2
              id="handled-allergens"
              className="font-display text-xl font-bold text-ink">
              
              Allergens handled in our kitchen
            </h2>
            <ul className="mt-4 flex flex-wrap gap-2">
              {ALLERGENS.map((allergen) =>
              <li
                key={allergen}
                className="rounded-full border border-ink/10 bg-white px-4 py-2 text-sm font-medium text-ink/75">
                
                  {allergen}
                </li>
              )}
            </ul>
          </section>

          <section aria-labelledby="before-you-order">
            <h2
              id="before-you-order"
              className="font-display text-xl font-bold text-ink">
              
              Before you order
            </h2>
            <ol className="mt-4 space-y-4">
              {[
              'Tell us about your allergy in writing — either in the kitchen notes at checkout or directly on WhatsApp.',
              'Wait for our confirmation. Our kitchen team will reply about whether we can safely prepare your selection.',
              'Confirm on the day. Recipes and suppliers can change, so we re-check every allergy order before cooking.'].
              map((step, index) =>
              <li key={step} className="flex gap-4">
                  <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-ink font-display text-sm font-bold text-white">
                    {index + 1}
                  </span>
                  <p className="pt-1 text-sm leading-relaxed text-ink/65">{step}</p>
                </li>
              )}
            </ol>
          </section>
        </article>

        <aside className="space-y-4 lg:sticky lg:top-24 lg:self-start">
          <section className="rounded-2xl border border-ink/10 bg-white p-6 shadow-card">
            <h2 className="font-display text-lg font-bold text-ink">
              Speak to the kitchen
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-ink/60">
              Message us before you order and we'll talk through your requirements
              dish by dish.
            </p>
            <Button
              className="mt-5 w-full bg-[#25D366] hover:bg-[#1EBE57]"
              onClick={() => openWhatsApp(buildAllergyEnquiryMessage())}>
              
              <MessageCircleIcon className="h-4 w-4" /> WhatsApp us
            </Button>
          </section>

          <section className="rounded-2xl border border-ink/10 bg-cream p-6">
            <h2 className="font-display text-lg font-bold text-ink">
              Ready to browse?
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-ink/60">
              Every dish lists its prep time and availability so you know exactly what
              you're ordering.
            </p>
            <Button asChild variant="outline" className="mt-5 w-full">
              <Link to="/menu">View the menu</Link>
            </Button>
          </section>
        </aside>
      </div>
    </div>);

}
