import React from 'react';
import { Link } from 'react-router-dom';

interface RefundSectionProps {
  id: string;
  title: string;
  children: React.ReactNode;
}

const CONTENTS = [
  ['about', 'About this Refund Policy'],
  ['cancelling', 'Cancelling an order'],
  ['perishable-food', 'Perishable food and change-of-mind cancellations'],
  ['cannot-fulfil', 'If we cannot fulfil your order'],
  ['missing-incorrect', 'Missing or incorrect items'],
  ['food-quality', 'Problems with food quality'],
  ['allergies', 'Allergies and food safety concerns'],
  ['delivery', 'Delivery problems'],
  ['payment', 'Payment problems and duplicate charges'],
  ['reporting', 'How to report a problem'],
  ['how-refunds-issued', 'How refunds are issued'],
  ['refund-timing', 'Refund timing'],
  ['evidence', 'Evidence we may reasonably request'],
  ['consumer-rights', 'Your consumer rights'],
  ['contact', 'Contact us']
] as const;

function RefundSection({ id, title, children }: RefundSectionProps) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24">
      <h2 id={`${id}-title`} className="font-display text-2xl font-bold text-ink sm:text-3xl">{title}</h2>
      <div className="mt-4 space-y-4 text-sm leading-relaxed text-ink/70 sm:text-base">{children}</div>
    </section>
  );
}

export function RefundPolicyPage() {
  return (
    <div className="w-full bg-cream">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">When things don&apos;t go to plan</p>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">Refund Policy</h1>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-ink/60 sm:text-base">What to do if you need to cancel an order or something isn&apos;t right with your SoYummy Foods order.</p>
          <p className="mt-5 text-xs font-medium uppercase tracking-[0.12em] text-ink/45">Last updated: September 2026</p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 lg:grid-cols-[13.5rem_minmax(0,1fr)] lg:px-8 lg:py-16">
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <nav aria-label="Refund Policy contents" className="rounded-2xl border border-ink/10 bg-white p-5 shadow-card">
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-500">Contents</p>
            <ol className="mt-4 space-y-1.5">
              {CONTENTS.map(([id, label], index) => <li key={id}><a href={`#${id}`} className="block rounded-lg px-2 py-1.5 text-sm leading-snug text-ink/65 transition-colors hover:bg-brand-50 hover:text-brand-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"><span className="mr-1.5 text-xs text-ink/35">{index + 1}.</span>{label}</a></li>)}
            </ol>
          </nav>
        </aside>

        <article className="max-w-3xl space-y-11">
          <RefundSection id="about" title="1. About this Refund Policy">
            <p>This Refund Policy explains how to contact SoYummy Foods if you need to cancel an order or if something is wrong with an order. It supplements, and does not limit, your rights under applicable UK consumer law.</p>
          </RefundSection>

          {/* CLIENT REVIEW: confirm operational cancellation cut-off and process. */}
          <RefundSection id="cancelling" title="2. Cancelling an order">
            <p>Please contact us as soon as possible if you need to change or cancel an order. Food preparation may begin shortly after payment and confirmation, so we may not always be able to accommodate a cancellation or change once preparation has begun.</p>
            <p>We will consider your request fairly in the circumstances. This policy does not create an automatic cancellation button, a fixed cancellation window, or an automatic right to edit a paid order.</p>
          </RefundSection>

          <RefundSection id="perishable-food" title="3. Perishable food and change-of-mind cancellations">
            <p>Prepared and perishable food may not benefit from the standard change-of-mind cancellation rights that apply to many other online purchases. That does not affect your separate rights if food is not as described, is not of satisfactory quality, is unsafe, is incorrect or missing, or is not delivered.</p>
          </RefundSection>

          <RefundSection id="cannot-fulfil" title="4. If we cannot fulfil your order">
            <p>If we cannot fulfil all or part of an accepted order, for example because an item becomes unavailable or delivery cannot be completed for reasons attributable to us, we will contact you and provide an appropriate refund or another agreed resolution for the affected part.</p>
            <p>We will not make an automatic substitution for a materially different item without your agreement.</p>
          </RefundSection>

          <RefundSection id="missing-incorrect" title="5. Missing or incorrect items">
            <p>If an item is missing or incorrect, please contact us promptly with your order number, the affected item or items, and a short explanation. We will review the issue and, where appropriate, may offer a suitable remedy such as a replacement, correction, partial refund, or refund depending on the circumstances.</p>
          </RefundSection>

          <RefundSection id="food-quality" title="6. Problems with food quality">
            <p>Please contact us promptly if food arrives damaged, appears spoiled, is materially different from its description, or otherwise appears not to meet reasonable quality expectations. Where appropriate, we may ask you not to consume food that you believe may be unsafe while we review the concern.</p>
          </RefundSection>

          <RefundSection id="allergies" title="7. Allergies and food safety concerns">
            <p>Read our <Link to="/allergy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">allergy advisory notice</Link> before ordering. If you believe you received incorrect allergen information or food that presents a safety concern, do not consume it and contact SoYummy Foods promptly.</p>
            <p>Nothing in this policy waives our legal responsibilities for allergen information, food safety, negligence, or your consumer rights.</p>
          </RefundSection>

          {/* CLIENT REVIEW: confirm delivery-failure/refund operational rules. */}
          <RefundSection id="delivery" title="8. Delivery problems">
            <p>If your order is not received, is materially incomplete, or there is another significant delivery issue affecting the order, please contact us promptly. We will review the circumstances and provide an appropriate resolution where we are responsible.</p>
          </RefundSection>

          <RefundSection id="payment" title="9. Payment problems and duplicate charges">
            <p>If you see a failed payment, an unexpected duplicate charge, payment taken without a corresponding confirmed order, or another payment discrepancy, please contact us with your order number and relevant payment information.</p>
            <p>Do not send a full card number, CVV or security code, online-banking password, or wallet credentials. A limited transaction reference or a screenshot with sensitive payment information obscured can be helpful. An apparent pending bank authorisation is not necessarily a completed SoYummy Foods charge.</p>
          </RefundSection>

          <RefundSection id="reporting" title="10. How to report a problem">
            <p>Contact us promptly with the order number, name used for the order, a description of the problem, and the affected item or items. Photographs can be useful where relevant, as can a limited payment reference for a payment concern.</p>
            <p>Please do not send full payment-card details, banking passwords, CVV codes, or other sensitive credentials.</p>
          </RefundSection>

          {/* CLIENT REVIEW: confirm actual refund processing method before final publication. */}
          <RefundSection id="how-refunds-issued" title="11. How refunds are issued">
            <p>Where a monetary refund is approved, we will ordinarily return it through the appropriate or original payment route where possible. The available method will depend on the circumstances and the payment involved.</p>
          </RefundSection>

          {/* CLIENT REVIEW: confirm operational refund-processing target. */}
          <RefundSection id="refund-timing" title="12. Refund timing">
            <p>We will process an approved refund without unreasonable delay. The time for funds to appear can also depend on your payment provider. Any applicable statutory refund deadlines remain unaffected.</p>
          </RefundSection>

          <RefundSection id="evidence" title="13. Evidence we may reasonably request">
            <p>We may reasonably ask for information needed to understand and verify a reported problem, such as photographs of an incorrect or damaged item or proof of purchase. What is useful will depend on the circumstances.</p>
            <p>We will keep requests proportionate. Photographs or a receipt are not an absolute prerequisite to exercising any statutory rights you may have.</p>
          </RefundSection>

          <RefundSection id="consumer-rights" title="14. Your statutory rights">
            <div className="rounded-2xl border border-brand-100 bg-brand-50 p-5 text-ink/75">
              <p className="font-semibold text-ink">Your statutory rights</p>
              <p className="mt-2">Nothing in this Refund Policy limits rights you have under applicable UK consumer law. Goods supplied to consumers are generally required to be as described, of satisfactory quality, and fit for purpose.</p>
            </div>
            <p>This is not exhaustive legal advice, and your rights can depend on the particular circumstances of an order.</p>
          </RefundSection>

          <RefundSection id="contact" title="15. Contact us">
            <p>Please email <a href="mailto:hello@soyummyfoods.co.uk" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">hello@soyummyfoods.co.uk</a> or call <a href="tel:+442079460192" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">+44 20 7946 0192</a> with any order concern.</p>
            <p>You can also write to us at Unit 12, Southwark Enterprise Hub, London, SE1 0AA. For related information, see our <Link to="/terms-and-conditions" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Terms &amp; Conditions</Link> and <Link to="/privacy-policy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Privacy Policy</Link>.</p>
          </RefundSection>
        </article>
      </div>
    </div>
  );
}
