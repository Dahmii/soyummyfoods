import React from 'react';
import { Link } from 'react-router-dom';

interface PolicySectionProps {
  id: string;
  title: string;
  children: React.ReactNode;
}

const CONTENTS = [
  ['about', 'About this Privacy Policy'],
  ['information-we-collect', 'Information we collect'],
  ['how-we-use-information', 'How we use your information'],
  ['lawful-bases', 'Our lawful bases for using your information'],
  ['payments', 'Payments'],
  ['delivery', 'Delivery and order fulfilment'],
  ['sharing', 'Service providers and sharing your information'],
  ['receipts', 'Receipts and transaction records'],
  ['contact-channels', 'WhatsApp, telephone and email'],
  ['storage-and-cookies', 'Website storage, cookies and similar technologies'],
  ['retention', 'How long we keep your information'],
  ['international-transfers', 'International transfers'],
  ['security', 'How we protect your information'],
  ['rights', 'Your data-protection rights'],
  ['children', "Children's privacy"],
  ['changes', 'Changes to this Privacy Policy'],
  ['contact', 'Contact us'],
  ['complaints', 'Complaints']
] as const;

function PolicySection({ id, title, children }: PolicySectionProps) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24">
      <h2 id={`${id}-title`} className="font-display text-2xl font-bold text-ink sm:text-3xl">{title}</h2>
      <div className="mt-4 space-y-4 text-sm leading-relaxed text-ink/70 sm:text-base">{children}</div>
    </section>
  );
}

export function PrivacyPolicyPage() {
  return (
    <div className="w-full bg-cream">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">Privacy &amp; your data</p>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">Privacy Policy</h1>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-ink/60 sm:text-base">How SoYummy Foods collects, uses and protects your information when you use our website and order from us.</p>
          <p className="mt-5 text-xs font-medium uppercase tracking-[0.12em] text-ink/45">Last updated: September 2026</p>
        </div>
      </section>

      <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 lg:grid-cols-[13.5rem_minmax(0,1fr)] lg:px-8 lg:py-16">
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <nav aria-label="Privacy Policy contents" className="rounded-2xl border border-ink/10 bg-white p-5 shadow-card">
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-brand-500">Contents</p>
            <ol className="mt-4 space-y-1.5">
              {CONTENTS.map(([id, label], index) => <li key={id}><a href={`#${id}`} className="block rounded-lg px-2 py-1.5 text-sm leading-snug text-ink/65 transition-colors hover:bg-brand-50 hover:text-brand-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"><span className="mr-1.5 text-xs text-ink/35">{index + 1}.</span>{label}</a></li>)}
            </ol>
          </nav>
        </aside>

        <article className="max-w-3xl space-y-11">
          <PolicySection id="about" title="1. About this Privacy Policy">
            <p>This Privacy Policy explains how SoYummy Foods handles personal information when you visit our website, contact us, or place a guest order. It describes our current website and ordering practices and should be read alongside any information we provide when collecting details from you.</p>
            <p>SoYummy Foods is used here as the business and trading identity shown on this website. This policy does not claim a particular incorporated legal entity, company number, or registered-office status.</p>
          </PolicySection>

          <PolicySection id="information-we-collect" title="2. Information we collect">
            <p>When you place a guest order, we may collect your name, email address, telephone number, delivery address, postcode, selected products, quantities, order details, and any optional kitchen note you choose to provide.</p>
            <p>We also create order, payment, and security records needed to operate the service, such as an order number, financial totals, payment status, timestamps, and limited technical identifiers used to protect checkout and prevent abuse. We do not currently offer customer accounts.</p>
            <p>Your delivery postcode is used to check delivery eligibility and calculate the applicable delivery price. We may also receive limited technical information from the devices and services used to access the website, including information needed to provide security, hosting, and payment functionality.</p>
          </PolicySection>

          <PolicySection id="how-we-use-information" title="3. How we use your information">
            <p>We use order and contact information to accept, process, verify, prepare, deliver, and support your order; to calculate delivery eligibility and pricing; and to respond to questions connected with an order.</p>
            <p>We use payment references and statuses to confirm payments securely, investigate failed or unusual payment events, maintain transaction records, and protect the website from fraud or misuse. We may also use relevant information to meet record-keeping obligations and operate the business responsibly.</p>
          </PolicySection>

          <PolicySection id="lawful-bases" title="4. Our lawful bases for using your information">
            {/* CLIENT REVIEW: confirm lawful-basis wording against the business's final operating model before publication. */}
            <p>Where we need your information to accept, process, and fulfil an order, we use it because it is necessary to perform or take steps connected with a contract with you. Where records must be kept to meet applicable obligations, we may use information for compliance with a legal obligation.</p>
            <p>We may also process limited information for our legitimate interests in keeping the service secure, preventing fraud or abuse, maintaining reliable business administration, and protecting our rights. These interests are balanced against your rights and interests. We do not rely on consent as the ordinary basis for processing an order.</p>
          </PolicySection>

          <PolicySection id="payments" title="5. Payments">
            <p>Card entry and available wallet payment entry are handled through Stripe&apos;s payment tools. SoYummy Foods&apos; application does not collect or store your full card number, CVV, card expiry date, or wallet credentials.</p>
            <p>We may retain limited transaction information needed to operate and evidence an order, including payment status, amount, currency, timestamps, and payment-provider references. Stripe processes payment information under its own privacy practices.</p>
          </PolicySection>

          <PolicySection id="delivery" title="6. Delivery and order fulfilment">
            <p>We use your name, telephone number, delivery address, postcode, order contents, and relevant notes to prepare and fulfil your order. Access to customer order information is limited to authorised team members who need it for operational fulfilment and support.</p>
            <p>We do not name delivery partners in this policy because the current website does not identify a particular third-party delivery provider.</p>
          </PolicySection>

          <PolicySection id="sharing" title="7. Service providers and sharing your information">
            {/* CLIENT REVIEW: confirm operational sharing, including delivery, accounting, support, and any other processors before final publication. */}
            <p>We use service providers that support the website and ordering service, including Stripe for payment processing, Supabase for application, database, authentication, and storage infrastructure, and Vercel for website hosting and delivery.</p>
            <p>We may share information with providers or professional advisers only where reasonably necessary to operate, secure, support, or comply with obligations connected with the service. We do not state that any particular delivery, accounting, or marketing provider is used unless that is confirmed separately.</p>
          </PolicySection>

          <PolicySection id="receipts" title="8. Receipts and transaction records">
            <p>For eligible verified payments, we may issue an immutable receipt containing customer, order, delivery, payment-reference, and transaction information. Receipt PDFs are stored privately and are available only through restricted administrative access.</p>
            <p>These records help us preserve an accurate transaction history and meet relevant operational, financial, and legal record-keeping requirements.</p>
          </PolicySection>

          <PolicySection id="contact-channels" title="9. WhatsApp, telephone and email">
            <p>If you click a WhatsApp link, you are taken to an external WhatsApp service. The website itself does not currently record WhatsApp conversations; WhatsApp&apos;s own privacy practices apply once you use that service.</p>
            <p>You may also contact us by telephone or email using the details on this website. Information you provide through those channels may be handled to respond to your enquiry or support an order.</p>
          </PolicySection>

          <PolicySection id="storage-and-cookies" title="10. Website storage, cookies and similar technologies">
            {/* CLIENT REVIEW: verify production third-party cookie and storage behaviour separately before launch. */}
            <p>We use browser session storage to maintain checkout and payment continuity within the same browser session. This can include non-secret checkout handoff information and a temporary payment-session capability used to securely continue a checkout.</p>
            <p>The website does not currently implement application-level advertising, behavioural profiling, or marketing analytics technology. Third-party services involved in payment, hosting, and application infrastructure may process technical information or use storage that is necessary to provide their services. We do not claim that no cookies or similar technologies are used in every circumstance.</p>
          </PolicySection>

          <PolicySection id="retention" title="11. How long we keep your information">
            {/* CLIENT REVIEW: confirm retention periods, accounting obligations, backup handling, and deletion processes before final publication. */}
            <p>We keep information only for as long as reasonably necessary for the purpose for which it was collected, including order fulfilment, support, security, dispute handling, and applicable legal or accounting requirements.</p>
            <p>Order, payment, receipt, and audit records are designed to preserve an accurate historical record. Different categories of information may therefore be retained for different periods. We do not publish fixed retention periods here until they have been confirmed for the business.</p>
          </PolicySection>

          <PolicySection id="international-transfers" title="12. International transfers">
            {/* CLIENT REVIEW: confirm provider regions, transfer arrangements, and safeguards before final publication. */}
            <p>Some service providers used to operate the website, payment service, or application infrastructure may process information internationally. Where applicable law requires safeguards for an international transfer, we will use appropriate safeguards required for that transfer.</p>
            <p>We do not specify hosting regions or a particular transfer mechanism here because those details must be confirmed against the live provider accounts and arrangements.</p>
          </PolicySection>

          <PolicySection id="security" title="13. How we protect your information">
            <p>We use measures designed to protect information, including access controls for operational data, server-side payment verification, restricted private storage for financial documents, rate limiting for public checkout flows, and audit records for relevant administrative activity.</p>
            <p>No website or internet transmission can be guaranteed completely secure. We encourage you to use secure devices and contact us promptly if you believe an order or payment interaction has been affected by unauthorised activity.</p>
          </PolicySection>

          <PolicySection id="rights" title="14. Your data-protection rights">
            <p>Depending on the circumstances and applicable law, you may have rights to request access to your personal information, correction of inaccurate information, erasure, restriction of processing, objection to certain processing, and data portability.</p>
            <p>These rights are not absolute and can depend on the reason we use the information and applicable legal obligations. To make a request, please use the contact details below. We may need to verify your identity before responding.</p>
          </PolicySection>

          <PolicySection id="children" title="15. Children&apos;s privacy">
            <p>If you are a parent or guardian and have concerns that a child has provided personal information through this website, please contact us. We will consider the request in line with applicable law and the circumstances of the information involved.</p>
          </PolicySection>

          <PolicySection id="changes" title="16. Changes to this Privacy Policy">
            <p>We may update this Privacy Policy when our website, ordering process, service providers, or legal obligations change. The latest version will be published on this page with its updated date.</p>
          </PolicySection>

          <PolicySection id="contact" title="17. Contact us">
            {/* CLIENT REVIEW: confirm legal entity and privacy contact details before final publication. */}
            <p>If you have a question about this Privacy Policy or how SoYummy Foods handles your information, please contact us at <a href="mailto:hello@soyummyfoods.co.uk" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">hello@soyummyfoods.co.uk</a> or call <a href="tel:+442079460192" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">+44 20 7946 0192</a>.</p>
            <p>You can also write to us using the contact address displayed in the website footer: Unit 12, Southwark Enterprise Hub, London, SE1 0AA. This is presented as a contact address only, not as a statement of registered-office status.</p>
          </PolicySection>

          <PolicySection id="complaints" title="18. Complaints">
            <p>Please contact SoYummy Foods first if you have a concern about how we handle your information, so that we can try to resolve it. You also have the right to complain to the UK Information Commissioner&apos;s Office.</p>
            <p><a href="https://ico.org.uk/" target="_blank" rel="noreferrer" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Visit the Information Commissioner&apos;s Office website</a>.</p>
          </PolicySection>

          <div className="rounded-2xl border border-brand-100 bg-brand-50 p-5 text-sm leading-relaxed text-ink/70">
            <p className="font-semibold text-ink">Questions about an order?</p>
            <p className="mt-1">For order help, please use the contact details above or return to the <Link to="/menu" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">menu</Link>.</p>
          </div>
        </article>
      </div>
    </div>
  );
}
