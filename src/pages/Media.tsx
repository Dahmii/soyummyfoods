import React from 'react';
import { SectionHeading } from '../components/SectionHeading';
import { GALLERY, VIDEOS, IMAGERY } from '../data/site';

export function MediaPage() {
  return (
    <div className="w-full bg-white">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <h1 className="font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">
            Media &amp; Gallery
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
            Peek into our bustling UK kitchens, explore our celebratory events, and
            watch standard-setting masterclasses on preparing our beloved West African
            classics.
          </p>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-5 py-14 lg:px-8 lg:py-20">
        <SectionHeading eyebrow="Gallery" title="Kitchen Stories & Food Gallery" />
        <ul className="mt-10 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {GALLERY.map((entry) =>
          <li
            key={entry.title}
            className="group relative overflow-hidden rounded-2xl bg-ink">
            
              <img
              src={entry.image}
              alt={entry.title}
              loading="lazy"
              className="aspect-[4/5] w-full object-cover opacity-90 transition-transform duration-500 group-hover:scale-105" />
            
              <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-ink/70 p-4 backdrop-blur-sm">
                <h3 className="font-display text-base font-bold text-white">
                  {entry.title}
                </h3>
                <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-white/70">
                  {entry.caption}
                </p>
              </div>
            </li>
          )}
        </ul>
      </section>

      <section className="border-y border-ink/10 bg-cream">
        <div className="mx-auto max-w-7xl px-5 py-14 lg:px-8 lg:py-20">
          <SectionHeading eyebrow="Watch" title="Video Features & Guides" />
          <div className="mt-10 grid gap-6 lg:grid-cols-2">
            {VIDEOS.map((video) =>
            <article
              key={video.title}
              className="overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card">
              
                <div className="relative">
                  <img
                  src={video.image}
                  alt={video.title}
                  loading="lazy"
                  className="aspect-video w-full object-cover" />
                
                  <span className="absolute bottom-4 left-4 rounded-md bg-ink/80 px-2 py-1 text-xs font-semibold text-white">
                    {video.duration}
                  </span>
                </div>
                <div className="p-5">
                  <div className="flex items-start justify-between gap-4">
                    <h3 className="font-display text-lg font-bold text-ink">
                      {video.title}
                    </h3>
                    <span className="shrink-0 text-xs font-medium text-ink/50">
                      {video.views}
                    </span>
                  </div>
                  <p className="mt-2 text-sm leading-relaxed text-ink/60">
                    {video.description}
                  </p>
                </div>
              </article>
            )}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-7xl px-5 py-14 lg:px-8 lg:py-20">
        <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-16">
          <div>
            <SectionHeading
              eyebrow="Behind the scenes"
              title="Pure Love, Time-Honored Tradition"
              description="True Nigerian cooking demands complete dedication. We simmer our peppers, blend our fresh grains, and hand-massage spices into our beef cutlets daily. In an era of shortcuts, we remain proudly committed to real slow-cooked perfection." />
            
            <div className="mt-8 flex items-center gap-3">
              <img
                src={IMAGERY.chef}
                alt=""
                className="h-11 w-11 rounded-full object-cover" />
              
              <div>
                <p className="text-sm font-semibold text-ink">Adebayo Bamson</p>
                <p className="text-xs text-ink/50">Founder &amp; Executive Chef</p>
              </div>
            </div>
          </div>
          <img
            src={IMAGERY.kitchenTeam}
            alt="Two chefs cooking together in the SoYummy Foods kitchen"
            className="rounded-2xl object-cover shadow-card" />
          
        </div>
      </section>
    </div>);

}
