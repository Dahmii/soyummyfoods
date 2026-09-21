import React from 'react';
import { Link } from 'react-router-dom';

interface NoticeSectionProps {
  id: string;
  title: string;
  children: React.ReactNode;
}

function NoticeSection({ id, title, children }: NoticeSectionProps) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24">
      <h2 id={`${id}-title`} className="font-display text-2xl font-bold text-ink sm:text-3xl">{title}</h2>
      <div className="mt-4 space-y-4 text-sm leading-relaxed text-ink/70 sm:text-base">{children}</div>
    </section>
  );
}

const LEGAL_LINKS = [
  { to: '/privacy-policy', title: 'Privacy Policy', description: 'How we handle personal information when you use the website or place an order.' },
  { to: '/terms-and-conditions', title: 'Terms & Conditions', description: 'The terms that apply to using the website and placing an order.' },
  { to: '/refund-policy', title: 'Refund Policy', description: 'What to do if you need to cancel an order or something is not right.' },
  { to: '/allergy', title: 'Allergy Information', description: 'Important allergy and cross-contamination information before ordering.' }
] as const;

export function LegalNoticePage() {
  return (
    <div className="w-full bg-cream">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">Website information</p>
          <h1 className="mt-4 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">Legal Notice</h1>
          <p className="mx-auto mt-4 max-w-2xl text-sm leading-relaxed text-ink/60 sm:text-base">Information about SoYummy Foods, this website and the terms that govern its content.</p>
          <p className="mt-5 text-xs font-medium uppercase tracking-[0.12em] text-ink/45">Last updated: September 2026</p>
        </div>
      </section>

      <article className="mx-auto max-w-3xl space-y-11 px-5 py-14 sm:py-16 lg:px-8">
        {/* CLIENT REVIEW: if SoYummy Foods is a registered company, add the full
            registered company name, company number, registered office address,
            and place of registration required for website/business disclosures. */}
        <NoticeSection id="website-operator" title="1. Website operator">
          <p>This website is operated under the SoYummy Foods trading name. This notice does not state an incorporated legal name, company number, VAT number, registered office, or place of registration that has not been confirmed.</p>
        </NoticeSection>

        <NoticeSection id="contact-information" title="2. Contact information">
          <p>You can contact SoYummy Foods by email at <a href="mailto:hello@soyummyfoods.co.uk" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">hello@soyummyfoods.co.uk</a>, by telephone on <a href="tel:+442079460192" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">+44 20 7946 0192</a>, or by writing to Unit 12, Southwark Enterprise Hub, London, SE1 0AA.</p>
          <p>The address is provided as a business contact address only and is not presented as a registered-office address.</p>
        </NoticeSection>

        <NoticeSection id="website-purpose" title="3. Website purpose">
          <p>This website provides information about SoYummy Foods, its menu and services, and enables customers to place food orders where available. The contractual terms that govern orders are set out in our <Link to="/terms-and-conditions" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">Terms &amp; Conditions</Link>.</p>
        </NoticeSection>

        {/* CLIENT REVIEW: confirm ownership/licensing of food photography,
            logo/branding and other supplied creative assets. */}
        <NoticeSection id="intellectual-property" title="4. Intellectual property">
          <p>Unless otherwise indicated, materials created for SoYummy Foods, including its branding, original text, graphics, layout, and other original website content, are protected by applicable intellectual-property laws.</p>
          <p>Third-party names, marks, photographs, services, and materials remain the property of their respective owners where applicable.</p>
        </NoticeSection>

        <NoticeSection id="use-of-content" title="5. Use of website content">
          <p>You may use the website normally for personal purposes, including browsing the menu and placing orders. You must not reproduce or commercially exploit original SoYummy Foods website content without permission where applicable.</p>
          <p>This does not restrict ordinary links to the website or use that is permitted by law.</p>
        </NoticeSection>

        <NoticeSection id="information-availability" title="6. Website information and availability">
          <p>We aim to keep website information accurate and the service available. Menu availability can change, prices may change for future orders, website availability can occasionally be interrupted, and minor errors may occur.</p>
          <p>This notice does not override an accepted order, consumer rights, food-safety obligations, or contractual commitments. Nothing in this Legal Notice limits rights or responsibilities that cannot lawfully be limited.</p>
        </NoticeSection>

        <NoticeSection id="third-party" title="7. Third-party links and services">
          <p>The site may contain links or integrations involving third-party services, including Stripe, WhatsApp, or external websites. A link or integration does not necessarily mean that SoYummy Foods controls or endorses all content on that service.</p>
          <p>Third-party services operate under their own applicable terms and privacy practices. This does not affect responsibilities that cannot lawfully be excluded.</p>
        </NoticeSection>

        <NoticeSection id="other-policies" title="8. Our other legal policies">
          <div className="grid gap-3 sm:grid-cols-2">
            {LEGAL_LINKS.map(({ to, title, description }) => (
              <Link key={to} to={to} className="group rounded-2xl border border-ink/10 bg-white p-5 transition-colors hover:border-brand-200 hover:bg-brand-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2">
                <p className="font-display text-lg font-bold text-ink group-hover:text-brand-700">{title}</p>
                <p className="mt-1.5 text-sm leading-relaxed text-ink/60">{description}</p>
              </Link>
            ))}
          </div>
        </NoticeSection>

        <NoticeSection id="changes" title="9. Changes to this Legal Notice">
          <p>We may update this Legal Notice as the website, business information, or applicable requirements change. The latest version will be published on this page with its updated date.</p>
        </NoticeSection>

        <NoticeSection id="contact" title="10. Contact us">
          <p>If you have a question about this Legal Notice, please email <a href="mailto:hello@soyummyfoods.co.uk" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">hello@soyummyfoods.co.uk</a> or call <a href="tel:+442079460192" className="font-semibold text-brand-700 underline decoration-brand-300 underline-offset-2 hover:text-brand-600">+44 20 7946 0192</a>.</p>
          <p>You can also write to SoYummy Foods at Unit 12, Southwark Enterprise Hub, London, SE1 0AA.</p>
        </NoticeSection>
      </article>
    </div>
  );
}
