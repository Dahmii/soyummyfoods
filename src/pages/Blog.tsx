import React, { useState } from 'react';
import { ArrowRightIcon, CheckCircle2Icon } from 'lucide-react';
import { Badge } from '../components/ui/badge';
import { Button } from '../components/ui/button';
import { Input } from '../components/ui/input';
import { BLOG_CATEGORIES, FEATURED_POST, POSTS, IMAGERY } from '../data/site';

export function BlogPage() {
  const [email, setEmail] = useState('');
  const [subscribed, setSubscribed] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);

  function handleSubscribe(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const isValid = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email);
    if (!isValid) {
      setEmailError('Enter a valid email address');
      return;
    }
    setEmailError(null);
    setSubscribed(true);
  }

  return (
    <div className="w-full bg-white">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <h1 className="font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">
            Blog &amp; Stories
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
            Unveil the deep history, nutritional science, and timeless family cooking
            secrets behind the most cherished culinary traditions of West Africa.
          </p>
        </div>
      </section>

      <div className="mx-auto grid max-w-7xl gap-10 px-5 py-14 lg:grid-cols-[minmax(0,1fr)_20rem] lg:px-8 lg:py-16">
        <div className="space-y-10">
          <article className="overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card">
            <img
              src={FEATURED_POST.image}
              alt={FEATURED_POST.title}
              className="aspect-[16/9] w-full object-cover" />
            
            <div className="p-6 sm:p-8">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <Badge variant="soft">Featured story</Badge>
                <span className="text-xs font-medium text-ink/50">
                  {FEATURED_POST.date} · {FEATURED_POST.readTime}
                </span>
              </div>
              <h2 className="mt-4 font-display text-2xl font-bold leading-snug text-ink sm:text-3xl">
                {FEATURED_POST.title}
              </h2>
              <p className="mt-3 text-sm leading-relaxed text-ink/60">
                {FEATURED_POST.excerpt}
              </p>
              <div className="mt-6 flex flex-wrap items-center justify-between gap-4">
                <div className="flex items-center gap-3">
                  <img src={IMAGERY.chef} alt="" className="h-10 w-10 rounded-full object-cover" />
                  <div>
                    <p className="text-sm font-semibold text-ink">Grace Tunde</p>
                    <p className="text-xs text-ink/50">Food Historian &amp; Writer</p>
                  </div>
                </div>
                <Button size="sm">
                  Read full article <ArrowRightIcon className="h-4 w-4" />
                </Button>
              </div>
            </div>
          </article>

          <div className="grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
            {POSTS.map((post) =>
            <article
              key={post.title}
              className="group flex flex-col overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card transition-shadow hover:shadow-lift">
              
                <img
                src={post.image}
                alt={post.title}
                loading="lazy"
                className="aspect-[4/3] w-full object-cover transition-transform duration-500 group-hover:scale-105" />
              
                <div className="flex flex-1 flex-col p-5">
                  <div className="flex items-center justify-between gap-2 text-[11px] font-semibold uppercase tracking-[0.1em]">
                    <span className="text-brand-500">{post.category}</span>
                    <span className="text-ink/40">{post.date}</span>
                  </div>
                  <h3 className="mt-3 font-display text-lg font-bold leading-snug text-ink">
                    {post.title}
                  </h3>
                  <p className="mt-2 line-clamp-3 text-sm leading-relaxed text-ink/60">
                    {post.excerpt}
                  </p>
                  <p className="mt-4 text-xs font-medium text-ink/50">{post.readTime}</p>
                </div>
              </article>
            )}
          </div>
        </div>

        <aside className="space-y-6">
          <section className="rounded-2xl border border-ink/10 bg-white p-5 shadow-card">
            <h2 className="font-display text-lg font-bold text-ink">Categories</h2>
            <ul className="mt-4 space-y-1">
              {BLOG_CATEGORIES.map((category) =>
              <li key={category.label}>
                  <button
                  type="button"
                  className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-sm text-ink/70 transition-colors hover:bg-brand-50 hover:text-brand-700">
                  
                    {category.label}
                    <span className="text-xs text-ink/40">{category.count}</span>
                  </button>
                </li>
              )}
            </ul>
          </section>

          <section className="rounded-2xl border border-brand-100 bg-brand-50 p-5">
            <h2 className="font-display text-lg font-bold text-ink">
              Taste the Stories
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-ink/60">
              Get our favourite Nigerian home-style recipes, food culture reviews and
              menu updates delivered straight to your inbox.
            </p>
            {subscribed ?
            <p
              role="status"
              className="mt-4 flex items-center gap-2 rounded-xl bg-white px-3 py-3 text-sm font-medium text-emerald-700">
              
                <CheckCircle2Icon className="h-4 w-4" /> You're subscribed. Welcome!
              </p> :

            <form onSubmit={handleSubscribe} noValidate className="mt-4 space-y-3">
                <label htmlFor="newsletter-email" className="sr-only">
                  Email address
                </label>
                <Input
                id="newsletter-email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="Enter your email"
                aria-invalid={emailError ? true : undefined} />
              
                {emailError ?
              <p role="alert" className="text-xs font-medium text-red-600">
                    {emailError}
                  </p> :
              null}
                <Button type="submit" className="w-full">
                  Subscribe
                </Button>
              </form>
            }
          </section>

          <section className="rounded-2xl border border-ink/10 bg-white p-5 shadow-card">
            <h2 className="font-display text-lg font-bold text-ink">Popular Stories</h2>
            <ul className="mt-4 space-y-4">
              {POSTS.slice(0, 3).map((post) =>
              <li key={`popular-${post.title}`}>
                  <p className="text-sm font-semibold leading-snug text-ink">
                    {post.title}
                  </p>
                  <p className="mt-1 text-xs text-ink/50">{post.readTime}</p>
                </li>
              )}
            </ul>
          </section>
        </aside>
      </div>
    </div>);

}