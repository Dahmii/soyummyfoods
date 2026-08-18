import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { ClockIcon, PlusIcon, StarIcon, CheckIcon } from 'lucide-react';
import { Badge } from '../ui/badge';
import { Button } from '../ui/button';
import { formatPrice } from '../../utils/currency';
import { effectivePrice, type MenuItem } from '../../types/menu';
import { useCartStore } from '../../hooks/useCartStore';
import { cn } from '../../utils/cn';

interface FoodCardProps {
  item: MenuItem;
  className?: string;
}

export function FoodCard({ item, className }: FoodCardProps) {
  const addItem = useCartStore((state) => state.addItem);
  const [justAdded, setJustAdded] = useState(false);
  const [imageLoaded, setImageLoaded] = useState(false);

  useEffect(() => {
    if (!justAdded) return;
    const timer = window.setTimeout(() => setJustAdded(false), 1400);
    return () => window.clearTimeout(timer);
  }, [justAdded]);

  const price = effectivePrice(item);
  const isDiscounted = price < item.price;

  function handleAdd() {
    addItem(item);
    setJustAdded(true);
  }

  return (
    <motion.article
      whileHover={{ y: -4 }}
      transition={{ type: 'spring', stiffness: 320, damping: 26 }}
      className={cn(
        'group flex h-full flex-col overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card transition-shadow hover:shadow-lift',
        !item.available && 'opacity-90',
        className
      )}>
      
      <div className="relative aspect-[4/3] overflow-hidden bg-cream-dark">
        {!imageLoaded ?
        <div className="absolute inset-0 animate-pulse bg-ink/10" aria-hidden="true" /> :
        null}
        <img
          src={item.image}
          alt={item.name}
          loading="lazy"
          onLoad={() => setImageLoaded(true)}
          className={cn(
            'h-full w-full object-cover transition-all duration-500 group-hover:scale-105',
            imageLoaded ? 'opacity-100' : 'opacity-0',
            !item.available && 'grayscale'
          )} />
        

        <div className="absolute left-3 top-3 flex flex-wrap gap-1.5">
          {item.tags.includes('special') ? <Badge>Today's Special</Badge> : null}
          {item.tags.includes('new') ? <Badge variant="dark">New</Badge> : null}
        </div>

        <span className="absolute right-3 top-3 inline-flex items-center gap-1 rounded-full bg-white/90 px-2.5 py-1 text-[11px] font-semibold text-ink backdrop-blur">
          <StarIcon className="h-3 w-3 fill-brand-500 text-brand-500" />
          {item.rating.toFixed(1)}
        </span>

        {!item.available ?
        <div className="absolute inset-0 flex items-center justify-center bg-ink/50">
            <span className="rounded-full bg-white px-4 py-1.5 text-xs font-semibold uppercase tracking-[0.1em] text-ink">
              Sold out today
            </span>
          </div> :
        null}
      </div>

      <div className="flex flex-1 flex-col p-5">
        <h3 className="font-display text-lg font-semibold leading-snug text-ink">
          {item.name}
        </h3>
        <p className="mt-2 line-clamp-2 text-sm leading-relaxed text-ink/60">
          {item.description}
        </p>

        <div className="mt-4 flex items-center gap-3 text-xs font-medium text-ink/60">
          <span className="inline-flex items-center gap-1.5">
            <ClockIcon className="h-3.5 w-3.5 text-brand-500" />
            {item.prepTimeMinutes} min prep
          </span>
          <span aria-hidden="true" className="h-1 w-1 rounded-full bg-ink/20" />
          {item.available ?
          <span className="inline-flex items-center gap-1.5 text-emerald-700">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-600" />
              Available now
            </span> :

          <span className="inline-flex items-center gap-1.5 text-ink/50">
              <span className="h-1.5 w-1.5 rounded-full bg-ink/40" />
              Unavailable
            </span>
          }
        </div>

        <div className="mt-5 flex items-center justify-between gap-3 border-t border-ink/10 pt-4">
          <div className="flex items-baseline gap-2">
            <span className="font-display text-xl font-bold text-ink">
              {formatPrice(price)}
            </span>
            {isDiscounted ?
            <span className="text-sm text-ink/40 line-through">
                {formatPrice(item.price)}
              </span> :
            null}
          </div>

          <Button
            size="sm"
            variant={justAdded ? 'dark' : 'default'}
            onClick={handleAdd}
            disabled={!item.available}
            aria-label={`Add ${item.name} to cart`}>
            
            {justAdded ?
            <>
                <CheckIcon className="h-4 w-4" /> Added
              </> :

            <>
                <PlusIcon className="h-4 w-4" /> Add to Cart
              </>
            }
          </Button>
        </div>
      </div>
    </motion.article>);

}

export function FoodCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card">
      <div className="aspect-[4/3] animate-pulse bg-ink/10" />
      <div className="space-y-3 p-5">
        <div className="h-5 w-3/4 animate-pulse rounded bg-ink/10" />
        <div className="h-4 w-full animate-pulse rounded bg-ink/10" />
        <div className="h-4 w-2/3 animate-pulse rounded bg-ink/10" />
        <div className="flex items-center justify-between pt-3">
          <div className="h-6 w-20 animate-pulse rounded bg-ink/10" />
          <div className="h-9 w-28 animate-pulse rounded-full bg-ink/10" />
        </div>
      </div>
    </div>);

}