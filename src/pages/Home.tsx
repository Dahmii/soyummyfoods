import React from 'react';
import { Link } from 'react-router-dom';
import { motion, useReducedMotion } from 'framer-motion';
import {
  StarIcon,
  ShieldCheckIcon,
  BadgeCheckIcon,
  ArrowRightIcon } from
'lucide-react';
import { Button } from '../components/ui/button';
import { FoodCard } from '../components/menu/FoodCard';
import { AllergyNotice } from '../components/AllergyNotice';
import { SectionHeading } from '../components/SectionHeading';
import { IMAGERY } from '../data/site';
import { useMenu } from '../hooks/useMenu';

const TRUST_SIGNALS = [
{
  Icon: StarIcon,
  label: '4.9/5 Star Rating from 1,200+ Foodies'
},
{
  Icon: ShieldCheckIcon,
  label: '5 · UK Food Standards Hygiene Rating'
},
{
  Icon: BadgeCheckIcon,
  label: 'HACCP & food safety certified'
}];


export function HomePage() {
  const { items } = useMenu();
  const reduceMotion = useReducedMotion();
  const signatureDishes = items.filter((item) =>
  item.tags.includes('popular')
  ).slice(0, 4);

  return (
    <div className="w-full bg-cream">
      {/* Hero */}
      <section aria-labelledby="home-hero-heading" className="relative isolate flex min-h-[34rem] overflow-hidden bg-ink sm:min-h-[38rem] lg:min-h-[42rem]">
        <img
          src={IMAGERY.hero}
          alt=""
          className="absolute inset-0 -z-20 h-full w-full object-cover"
        />
        <div aria-hidden="true" className="absolute inset-0 -z-10 bg-gradient-to-r from-black/75 via-black/50 to-black/15" />
        <div className="mx-auto flex w-full max-w-7xl items-end px-5 py-14 sm:px-8 sm:py-16 lg:px-8 lg:py-20">
          <motion.div
            initial={reduceMotion ? false : { opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: reduceMotion ? 0 : 0.5, ease: 'easeOut' }}
            className="relative -top-24 max-w-3xl"
          >
            <h1 id="home-hero-heading" className="font-display text-5xl font-semibold leading-[0.98] tracking-[-0.035em] text-white sm:text-6xl lg:text-7xl">
              Authentic Nigerian Flavours, Made with Love.
            </h1>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Button asChild size="lg" className="w-full bg-brand-500 text-white hover:bg-brand-600 sm:w-auto">
                <Link to="/menu">Explore Our Menu</Link>
              </Button>
              <Button asChild size="lg" variant="outline" className="w-full border-white/65 bg-white/10 text-white hover:border-white hover:bg-white hover:text-ink focus-visible:ring-white sm:w-auto">
                <a href="#our-story">Our Story</a>
              </Button>
            </div>
          </motion.div>
        </div>
      </section>

      {/* Story */}
      <section id="our-story" className="border-b border-ink/10 bg-cream">
        <div className="mx-auto grid max-w-7xl items-center gap-10 px-5 py-16 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1fr)] lg:gap-16 lg:px-8 lg:py-20">
          <div className="relative">
            <div className="absolute -bottom-4 -right-4 hidden h-full w-full rounded-2xl border-2 border-brand-500 lg:block" />
            <img
              src={IMAGERY.foods}
              alt="A chef preparing fresh vegetables and spices in the SoYummy kitchen"
              className="relative h-full w-full rounded-2xl object-cover shadow-card" />
            
          </div>

          <div>
            <SectionHeading
              eyebrow="Our story"
              title="A Passion for Nigerian Cuisine, Crafted for the UK" />
            
            <div className="mt-5 space-y-4 text-sm leading-relaxed text-ink/60 sm:text-base">
              <p>
                At SoYummy Foods, our journey started with a simple, powerful mission:
                to share the deep, vibrant and soul-satisfying tastes of Nigeria with
                food lovers across the United Kingdom. We combine years of heritage
                culinary expertise with locally sourced, premium fresh ingredients.
              </p>
              <p>
                Every single dish that leaves our kitchen is slow-cooked, richly spiced
                and prepared according to timeless ancestral recipes. We take no
                shortcuts, because authentic Nigerian food isn't just about sustenance —
                it's about warmth, celebration and absolute delight.
              </p>
            </div>
            
          </div>
        </div>
      </section>

      {/* Signature dishes */}
      <section className="border-b border-ink/10 bg-white">
        <div className="mx-auto max-w-7xl px-5 py-16 lg:px-8 lg:py-20">
          <SectionHeading
            eyebrow="The classics"
            title="Our Best-Selling Signature Dishes"
            description=""
            align="center" />
          
          <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {signatureDishes.map((item) =>
            <FoodCard key={item.id} item={item} />
            )}
          </div>
          <div className="mt-10 flex justify-center">
            <Button asChild variant="outline" size="lg">
              <Link to="/menu">
                See the full menu <ArrowRightIcon className="h-4 w-4" />
              </Link>
            </Button>
          </div>
        </div>
      </section>

      {/* Allergy advisory */}
      <section className="bg-cream">
        <div className="mx-auto max-w-7xl px-5 pt-10 lg:px-8">
          <AllergyNotice />
        </div>
      </section>

      {/* Trust bar */}
      <section aria-label="Trust and certifications" className="bg-cream">
        <ul className="mx-auto grid max-w-7xl gap-4 px-5 py-8 sm:grid-cols-3 lg:px-8">
          {TRUST_SIGNALS.map(({ Icon, label }) =>
          <li
            key={label}
            className="flex items-center gap-3 text-sm font-medium text-ink/70">
            
              <Icon className="h-5 w-5 shrink-0 text-brand-500" />
              {label}
            </li>
          )}
        </ul>
      </section>

      {/* Quote band */}
      <section className="bg-brand-500">
        <div className="mx-auto max-w-4xl px-5 py-16 text-center lg:px-8">
          <p className="font-display text-3xl font-bold leading-snug text-white sm:text-4xl">
            “Where Every Bite Tells a Story of Home”
          </p>
          <p className="mt-4 text-sm font-medium uppercase tracking-[0.16em] text-white/80">
            From our kitchen to your table, made with pure love &amp; tradition
          </p>
        </div>
      </section>
    </div>);

}
