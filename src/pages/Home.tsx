import React from 'react';
import { Link } from 'react-router-dom';
import { motion } from 'framer-motion';
import {
  StarIcon,
  ShieldCheckIcon,
  BadgeCheckIcon,
  ArrowRightIcon } from
'lucide-react';
import { Button } from '../components/ui/button';
import { Badge } from '../components/ui/badge';
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
  const signatureDishes = items.filter((item) =>
  item.tags.includes('popular')
  ).slice(0, 4);

  return (
    <div className="w-full bg-cream">
      {/* Hero */}
      <section className="border-b border-ink/10 bg-white">
        <div className="mx-auto grid max-w-7xl items-center gap-10 px-5 py-14 lg:grid-cols-2 lg:gap-14 lg:px-8 lg:py-20">
          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}>
            
            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">
              Now delivering nationwide across the UK
            </p>
            <h1 className="mt-4 font-display text-4xl font-bold leading-[1.08] text-ink sm:text-5xl lg:text-6xl">
              Taste the Soul of Nigeria, Right Here in the UK
            </h1>
            <p className="mt-5 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
              Savor carefully crafted, authentic Nigerian culinary classics. From
              aromatic smoky Jollof Rice to rich Ofada Rice &amp; Ayamase, we bring the
              vibrant flavours of home directly to your table with unparalleled
              convenience and fresh ingredients.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Button asChild size="lg">
                <Link to="/menu">Order Now</Link>
              </Button>
              <Button asChild size="lg" variant="outline">
                <Link to="/menu">Bulk Order</Link>
              </Button>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, scale: 0.97 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.6, delay: 0.1 }}
            className="relative overflow-hidden rounded-2xl shadow-lift">
            
            <img
              src={IMAGERY.hero}
              alt="A table laid with Nigerian dishes including party jollof rice, egusi soup and beef suya"
              className="h-full w-full object-cover" />
            
            <Badge className="absolute right-4 top-4">100% Authentic Flavours</Badge>
          </motion.div>
        </div>
      </section>

      {/* Story */}
      <section className="border-b border-ink/10 bg-cream">
        <div className="mx-auto grid max-w-7xl items-center gap-10 px-5 py-16 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1fr)] lg:gap-16 lg:px-8 lg:py-20">
          <div className="relative">
            <div className="absolute -bottom-4 -right-4 hidden h-full w-full rounded-2xl border-2 border-brand-500 lg:block" />
            <img
              src={IMAGERY.chef}
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
            <dl className="mt-8 flex gap-12">
              <div>
                <dt className="sr-only">Authentic recipes</dt>
                <dd className="font-display text-3xl font-bold text-brand-500">100%</dd>
                <p className="mt-1 text-xs font-medium uppercase tracking-[0.12em] text-ink/50">
                  Authentic recipes
                </p>
              </div>
              <div>
                <dt className="sr-only">Happy customers</dt>
                <dd className="font-display text-3xl font-bold text-brand-500">15k+</dd>
                <p className="mt-1 text-xs font-medium uppercase tracking-[0.12em] text-ink/50">
                  Happy customers
                </p>
              </div>
            </dl>
          </div>
        </div>
      </section>

      {/* Signature dishes */}
      <section className="border-b border-ink/10 bg-white">
        <div className="mx-auto max-w-7xl px-5 py-16 lg:px-8 lg:py-20">
          <SectionHeading
            eyebrow="The classics"
            title="Our Best-Selling Signature Dishes"
            description="Add any plate straight to your basket — no menus to dig through, no detail pages to open."
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
