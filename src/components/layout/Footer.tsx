import React from 'react';
import { Link } from 'react-router-dom';
import {
  InstagramIcon,
  FacebookIcon,
  TwitterIcon,
  MailIcon,
  PhoneIcon,
  MapPinIcon,
  GlobeIcon,
  MessageCircleIcon } from
'lucide-react';
import { Logo } from './Logo';
import { buildCateringEnquiryMessage, openWhatsApp } from '../../utils/whatsapp';

const EXPLORE = [
{ to: '/', label: 'Home' },
{ to: '/menu', label: 'Our Menu' },
{ to: '/menu', label: 'Bulk Orders' },
{ to: '/blog', label: 'Blog' },
{ to: '/allergy', label: 'Allergy Advisory' },
{ to: '/media', label: 'Get in Touch' }];


const SOCIALS = [
{ Icon: InstagramIcon, label: 'Instagram' },
{ Icon: FacebookIcon, label: 'Facebook' },
{ Icon: TwitterIcon, label: 'Twitter' },
{ Icon: GlobeIcon, label: 'Website' }];


export function Footer() {
  return (
    <footer className="bg-ink text-white">
      <div className="mx-auto grid max-w-7xl gap-10 px-5 py-14 sm:grid-cols-2 lg:grid-cols-4 lg:px-8">
        <div className="lg:col-span-2">
          <Logo tone="dark" />
          <p className="mt-4 max-w-xs text-sm leading-relaxed text-white/60">
            Bringing authentic and traditional Nigerian recipes right to your UK
            doorstep. Slow cooked with premium, fresh ingredients.
          </p>
        </div>

        <div>
          <h2 className="text-xs font-semibold uppercase tracking-[0.16em] text-white/80">
            Explore
          </h2>
          <ul className="mt-4 space-y-2.5">
            {EXPLORE.map((link) =>
            <li key={link.label}>
                <Link
                to={link.to}
                className="text-sm text-white/60 transition-colors hover:text-brand-400">
                
                  {link.label}
                </Link>
              </li>
            )}
          </ul>
        </div>

        <div>
          <h2 className="text-xs font-semibold uppercase tracking-[0.16em] text-white/80">
            Contact Us
          </h2>
          <ul className="mt-4 space-y-3 text-sm text-white/60">
            <li className="flex items-start gap-2.5">
              <PhoneIcon className="mt-0.5 h-4 w-4 shrink-0 text-brand-500" />
              <a href="tel:+442079460192" className="hover:text-brand-400">
                +44 20 7946 0192
              </a>
            </li>
            <li className="flex items-start gap-2.5">
              <MailIcon className="mt-0.5 h-4 w-4 shrink-0 text-brand-500" />
              <a href="mailto:hello@soyummyfoods.co.uk" className="hover:text-brand-400">
                hello@soyummyfoods.co.uk
              </a>
            </li>
            <li className="flex items-start gap-2.5">
              <MessageCircleIcon className="mt-0.5 h-4 w-4 shrink-0 text-[#25D366]" />
              <button
                type="button"
                onClick={() => openWhatsApp(buildCateringEnquiryMessage())}
                className="text-left hover:text-brand-400">
                
                Order or enquire on WhatsApp
              </button>
            </li>
            <li className="flex items-start gap-2.5">
              <MapPinIcon className="mt-0.5 h-4 w-4 shrink-0 text-brand-500" />
              <span>Unit 12, Southwark Enterprise Hub, London, SE1 0AA</span>
            </li>
          </ul>
          <p className="mt-4 text-xs leading-relaxed text-white/40">
            Our kitchen handles gluten, fish, crustaceans, soybeans, nuts, seeds and
            eggs.{' '}
            <Link to="/allergy" className="font-semibold text-white/70 hover:text-brand-400">
              Allergy advisory notice
            </Link>
          </p>
        </div>
      </div>

      <div className="border-t border-white/10">
        <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-4 px-5 py-6 sm:flex-row lg:px-8">
          <p className="text-xs text-white/40">
            © {new Date().getFullYear()} SoYummy Foods UK. All rights reserved.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-5">
            <nav aria-label="Legal">
              <ul className="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
                <li>
                  <Link to="/privacy-policy" className="text-xs font-medium text-white/60 transition-colors hover:text-brand-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-400 focus-visible:ring-offset-2 focus-visible:ring-offset-ink">
                    Privacy Policy
                  </Link>
                </li>
                <li>
                  <Link to="/terms-and-conditions" className="text-xs font-medium text-white/60 transition-colors hover:text-brand-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-400 focus-visible:ring-offset-2 focus-visible:ring-offset-ink">
                    Terms &amp; Conditions
                  </Link>
                </li>
                <li>
                  <Link to="/refund-policy" className="text-xs font-medium text-white/60 transition-colors hover:text-brand-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-400 focus-visible:ring-offset-2 focus-visible:ring-offset-ink">
                    Refund Policy
                  </Link>
                </li>
                <li>
                  <Link to="/legal-notice" className="text-xs font-medium text-white/60 transition-colors hover:text-brand-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-400 focus-visible:ring-offset-2 focus-visible:ring-offset-ink">
                    Legal Notice
                  </Link>
                </li>
              </ul>
            </nav>
            <ul className="flex items-center gap-2">
              {SOCIALS.map(({ Icon, label }) =>
              <li key={label}>
                  <a
                  href="#"
                  aria-label={label}
                  className="flex h-9 w-9 items-center justify-center rounded-full bg-white/10 text-white/70 transition-colors hover:bg-brand-500 hover:text-white">

                    <Icon className="h-4 w-4" />
                  </a>
                </li>
              )}
            </ul>
          </div>
        </div>
      </div>
    </footer>);

}
