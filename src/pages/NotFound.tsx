import React from 'react';
import { Link } from 'react-router-dom';
import { ArrowRightIcon, HouseIcon, UtensilsCrossedIcon } from 'lucide-react';
import { Button } from '../components/ui/button';

export function NotFoundPage() {
  return (
    <section className="relative overflow-hidden bg-cream" aria-labelledby="not-found-title">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-48 bg-[radial-gradient(circle_at_center,rgba(242,102,28,0.12),transparent_68%)]" aria-hidden="true" />
      <div className="relative mx-auto flex min-h-[calc(100vh-16rem)] max-w-7xl items-center px-5 py-14 sm:py-20 lg:px-8 lg:py-24">
        <div className="mx-auto w-full max-w-2xl text-center">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">Wrong turn, deliciously speaking</p>

          <div className="relative mx-auto mt-7 flex h-32 max-w-md items-center justify-center gap-2 sm:mt-9 sm:h-40 sm:gap-5" aria-hidden="true">
            <span className="font-display text-7xl font-black leading-none text-ink sm:text-8xl">4</span>
            <div className="relative flex h-28 w-28 items-center justify-center sm:h-36 sm:w-36">
              <UtensilsCrossedIcon className="absolute -left-5 top-2 h-7 w-7 -rotate-12 text-brand-500/70 sm:-left-7 sm:h-8 sm:w-8" strokeWidth={1.5} />
              <div className="absolute inset-0 rounded-full border-[9px] border-white bg-cream-dark shadow-card sm:border-[11px]" />
              <div className="absolute inset-[15%] rounded-full border border-ink/10 bg-cream sm:inset-[16%]" />
              <span className="absolute left-[37%] top-[40%] h-1.5 w-1.5 rounded-full bg-brand-500/70" />
              <span className="absolute left-[55%] top-[54%] h-1 w-1 rounded-full bg-ink/30" />
              <span className="absolute left-[47%] top-[62%] h-1 w-1 rounded-full bg-brand-500/50" />
            </div>
            <span className="font-display text-7xl font-black leading-none text-ink sm:text-8xl">4</span>
          </div>

          <h1 id="not-found-title" className="mt-8 font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">
            Looks like this plate is empty.
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
            We couldn&apos;t find what you were looking for. It may have moved, sold out, or perhaps it was never on the menu.
          </p>

          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
            <Button asChild size="lg">
              <Link to="/menu">
                Back to Menu <ArrowRightIcon className="h-4 w-4" aria-hidden="true" />
              </Link>
            </Button>
            <Button asChild size="lg" variant="outline">
              <Link to="/">
                <HouseIcon className="h-4 w-4" aria-hidden="true" /> Go Home
              </Link>
            </Button>
          </div>

          <div className="mx-auto mt-10 max-w-md border-t border-ink/10 pt-6">
            <p className="font-display text-lg font-bold text-ink">Still hungry?</p>
            <p className="mt-1 text-sm leading-relaxed text-ink/60">
              Head back to the menu and find something worth staying for.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
