import React from 'react';
import { Link } from 'react-router-dom';

interface TermsSectionProps {
  id: string;
  title: string;
  children: React.ReactNode;
}

const CONTENTS = [
  ['about', 'About these Terms'],
  ['about-soyummy', 'About SoYummy Foods'],
  ['using-website', 'Using our website'],
  ['menu-information', 'Our menu and product information'],
  ['allergies', 'Allergies and dietary requirements'],
  ['prices', 'Prices and delivery charges'],
  ['placing-order', 'Placing an order'],
  ['acceptance', 'Order acceptance'],
  ['payment', 'Payment'],
  ['availability', 'Availability and substitutions'],
  ['delivery', 'Delivery'],
  ['changes-cancellations', 'Changes and cancellations'],
  ['refunds', 'Refunds and problems with an order'],
  ['consumer-rights', 'Your consumer rights'],
  ['responsibility', 'Our responsibility to you'],
  ['events', 'Events outside our reasonable control'],
  ['personal-information', 'Personal information'],
  ['changes-terms', 'Changes to these Terms'],
  ['law-disputes', 'Governing law and disputes'],
  ['contact', 'Contact us']
] as const;

function TermsSection({ id, title, children }: TermsSectionProps) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24">
      <h2 id={`${id}-title`} className="font-display text-2xl font-bold text-ink sm:text-3xl">{title}</h2>
      <div className="mt-4 space-y-4 text-sm leading-relaxed text-ink/70 sm:text-base">{children}</div>
    </section>
  );
}

export function TermsAndConditionsPage() {
  return (
    <div className="w-full bg-cream">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">Ordering with SoYummy</p>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">Terms &amp; Conditions</h1>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-ink/60 sm:text-base">The terms that apply when you use our website and place an order with SoYummy Foods.</p>
          <p className="mt-5 text-xs font-medium uppercase tracking-[0.12em] text-ink/45">Last updated: September 2026</p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 lg:grid-cols-[13.5rem_minmax(0,1fr)] lg:px-8 lg:py-16">
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <nav aria-label="Terms and Conditions contents" className="rounded-2xl border border-ink/10 bg-white p-5 shadow-card">
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-500">Contents</p>
            <ol className="mt-4 space-y-1.5">
              {CONTENTS.map(([id, label], index) => <li key={id}><a href={`#${id}`} className="block rounded-lg px-2 py-1.5 text-sm leading-snug text-ink/65 transition-colors hover:bg-brand-50 hover:text-brand-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"><span className="mr-1.5 text-xs text-ink/35">{index + 1}.</span>{label}</a></li>)}
            </ol>
          </nav>
        </aside>

        <article className="max-w-3xl space-y-11">
          <TermsSection id="about" title="1. About these Terms">
            <p>These Terms &amp; Conditions apply when you use the SoYummy Foods website or place an order with us. They explain how the website and ordering process work, alongside any information we provide at checkout.</p>
          </TermsSection>

          {/* CLIENT REVIEW: confirm legal entity and formal business details before final publication. */}
          <TermsSection id="about-soyummy" title="2. About SoYummy Foods">
            <p>SoYummy Foods is the trading identity shown on this website. These Terms do not state a particular incorporated legal entity, company number, VAT registration, or registered-office status.</p>
          </TermsSection>

          <TermsSection id="using-website" title="3. Using our website">
            <p>You may use this website for lawful personal ordering and information purposes. You must not deliberately interfere with its operation, security, or availability, or attempt to use it in a way that could harm the service or other users.</p>
          </TermsSection>

          <TermsSection id="menu-information" title="4. Our menu and product information">
            <p>We aim to keep menu descriptions, images, and product information accurate. Food presentation can naturally vary, images are illustrative, and menu availability may change.</p>
            <p>Food information is not a guarantee that an item is suitable for every allergy, intolerance, dietary preference, or medical requirement.</p>
          </TermsSection>

          <TermsSection id="allergies" title="5. Allergies and dietary requirements">
            <p>Please review our <Link to="/allergy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">allergy advisory notice</Link> before ordering. Our kitchen handles gluten, fish, crustaceans, soybeans, nuts, seeds, eggs, and other ingredients, and we cannot guarantee that food is free from cross-contamination.</p>
            <p>If you have an allergy or dietary requirement, please contact us before ordering so that we can discuss the item with you. We do not ask you to rely on website information alone where food safety is important.</p>
          </TermsSection>

          <TermsSection id="prices" title="6. Prices and delivery charges">
            <p>Menu prices are shown on the website. Delivery fees are calculated during checkout based on the delivery postcode and any applicable delivery rules. Your final total is calculated securely by our ordering system and shown before payment.</p>
            <p>Prices may change for future orders, but an accepted order will keep the price and delivery charge that applied to it. We do not add hidden charges through these Terms.</p>
          </TermsSection>

          <TermsSection id="placing-order" title="7. Placing an order">
            <p>Orders are placed as a guest. You provide contact and delivery details, the products and quantities you want, and any optional note for the kitchen. You are responsible for making sure this information is accurate and complete.</p>
            <p>Submitting checkout details or payment information does not by itself mean that we have accepted your order.</p>
          </TermsSection>

          {/* CLIENT REVIEW: confirm operational order-acceptance/cancellation process. */}
          <TermsSection id="acceptance" title="8. Order acceptance">
            <p>We accept an order when payment has been verified and the order is confirmed in our ordering system. If we cannot accept an order because of availability, delivery, pricing, or a system issue, we will let you know and handle any payment appropriately.</p>
          </TermsSection>

          <TermsSection id="payment" title="9. Payment">
            <p>Payments are processed through Stripe using the payment methods shown at checkout. Payment must normally be completed before we fulfil an order.</p>
            <p>Our application does not handle or store your full card number, CVV, card expiry date, or wallet credentials. Stripe processes payment information under its own terms and privacy practices.</p>
          </TermsSection>

          <TermsSection id="availability" title="10. Availability and substitutions">
            <p>Items can become unavailable after they are displayed on the menu. We will not substitute a materially different item without your agreement. If an item or order is affected, we will contact you where appropriate and handle it in line with our <Link to="/refund-policy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Refund Policy</Link>.</p>
          </TermsSection>

          {/* CLIENT REVIEW: confirm delivery operations, failed-delivery rules and any delivery partners. */}
          <TermsSection id="delivery" title="11. Delivery">
            <p>Delivery depends on the areas and postcodes we serve. Please provide an accurate delivery address and a telephone number on which we can reach you if needed. Delivery estimates are subject to preparation times, traffic, and circumstances outside our reasonable control.</p>
          </TermsSection>

          <TermsSection id="changes-cancellations" title="12. Changes and cancellations">
            <p>Food preparation may begin after an order is confirmed, so please contact us as soon as possible if you need to change or cancel an order. We will try to help where we reasonably can, but not every change can be accommodated.</p>
            <p>Your options depend on the circumstances, the goods involved, and applicable consumer law. Please also see our <Link to="/refund-policy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Refund Policy</Link>.</p>
          </TermsSection>

          <TermsSection id="refunds" title="13. Refunds and problems with an order">
            <p>If an order is not supplied, is incorrect, is damaged, or is not reasonably what you expected, please contact us promptly with your order details so that we can investigate and put matters right where appropriate.</p>
            <p>Our <Link to="/refund-policy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Refund Policy</Link> will provide further guidance when published. Nothing in it or these Terms removes rights that you have under consumer law.</p>
          </TermsSection>

          <TermsSection id="consumer-rights" title="14. Your consumer rights">
            <p>Nothing in these Terms affects your statutory rights as a consumer in the United Kingdom.</p>
          </TermsSection>

          {/* CLIENT REVIEW: liability wording requires final legal/business review. */}
          <TermsSection id="responsibility" title="15. Our responsibility to you">
            <p>We are responsible for losses that are a foreseeable result of our breach of these Terms or our failure to use reasonable care and skill. We are not responsible for losses that are not foreseeable or that arise from circumstances outside our reasonable control, to the extent permitted by law.</p>
            <p>Nothing in these Terms excludes or limits liability where it would be unlawful to do so, including liability for death or personal injury caused by negligence, fraud, or any statutory rights that cannot lawfully be excluded.</p>
          </TermsSection>

          <TermsSection id="events" title="16. Events outside our reasonable control">
            <p>Sometimes events outside our reasonable control, such as severe weather, transport disruption, utility failures, or service outages, can affect the website, preparation, or delivery. Where this happens, we will take reasonable steps to minimise the impact and communicate with you where appropriate.</p>
          </TermsSection>

          <TermsSection id="personal-information" title="17. Personal information">
            <p>Our <Link to="/privacy-policy" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Privacy Policy</Link> explains how we handle personal information when you use the website or place an order.</p>
          </TermsSection>

          <TermsSection id="changes-terms" title="18. Changes to these Terms">
            <p>We may update these Terms for future use of the website or future orders. Changes will not retrospectively change an order we have already accepted, except where required by law or agreed with you.</p>
          </TermsSection>

          {/* CLIENT REVIEW: confirm governing-law/business-jurisdiction wording before final publication. */}
          <TermsSection id="law-disputes" title="19. Governing law and disputes">
            <p>These Terms are intended to operate in accordance with applicable law. Nothing here limits any mandatory protections or rights available to you under consumer law.</p>
          </TermsSection>

          <TermsSection id="contact" title="20. Contact us">
            <p>If you have a question about these Terms or an order, please email <a href="mailto:hello@soyummyfoods.co.uk" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">hello@soyummyfoods.co.uk</a> or call <a href="tel:+442079460192" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">+44 20 7946 0192</a>.</p>
            <p>You can also write to us at Unit 12, Southwark Enterprise Hub, London, SE1 0AA. This is presented as a contact address only, not as a statement of registered-office status.</p>
          </TermsSection>

          <div className="rounded-2xl border border-brand-100 bg-brand-50 p-5 text-sm leading-relaxed text-ink/70">
            <p className="font-semibold text-ink">Ready to order?</p>
            <p className="mt-1">Return to the <Link to="/menu" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">menu</Link> to see what&apos;s available today.</p>
          </div>
        </article>
      </div>
    </div>
  );
}
