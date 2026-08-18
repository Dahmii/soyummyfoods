import React, { useMemo, useState } from 'react';
import { AlertTriangleIcon, FlameIcon, SparklesIcon, TagIcon } from 'lucide-react';
import { FoodCard, FoodCardSkeleton } from '../components/menu/FoodCard';
import { MenuFilters, type CategoryFilter } from '../components/menu/MenuFilters';
import { SectionHeading } from '../components/SectionHeading';
import { Button } from '../components/ui/button';
import { useMenu } from '../hooks/useMenu';
import { effectivePrice, type MenuItem, type SortOption } from '../types/menu';

function sortItems(items: MenuItem[], sort: SortOption): MenuItem[] {
  const copy = [...items];
  switch (sort) {
    case 'price-asc':
      return copy.sort((a, b) => effectivePrice(a) - effectivePrice(b));
    case 'price-desc':
      return copy.sort((a, b) => effectivePrice(b) - effectivePrice(a));
    case 'prep-time':
      return copy.sort((a, b) => a.prepTimeMinutes - b.prepTimeMinutes);
    default:
      return copy.sort(
        (a, b) => Number(b.available) - Number(a.available) || b.rating - a.rating
      );
  }
}

export function MenuPage() {
  const { items, isLoading, error, retry } = useMenu();
  const [query, setQuery] = useState('');
  const [category, setCategory] = useState<CategoryFilter>('all');
  const [sort, setSort] = useState<SortOption>('featured');

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    const matched = items.filter((item) => {
      const matchesQuery =
      normalized.length === 0 ||
      item.name.toLowerCase().includes(normalized) ||
      item.description.toLowerCase().includes(normalized);
      const matchesCategory = category === 'all' || item.category === category;
      return matchesQuery && matchesCategory;
    });
    return sortItems(matched, sort);
  }, [items, query, category, sort]);

  const isBrowsingAll = query.trim().length === 0 && category === 'all';
  const specials = items.filter((item) => item.tags.includes('special'));
  const popular = items.filter((item) => item.tags.includes('popular'));
  const newArrivals = items.filter((item) => item.tags.includes('new'));

  return (
    <div className="w-full bg-cream">
      <section className="border-b border-ink/10 bg-cream-dark">
        <div className="mx-auto max-w-3xl px-5 py-14 text-center sm:py-20 lg:px-8">
          <h1 className="font-display text-4xl font-bold leading-tight text-ink sm:text-5xl">
            Our Menu
          </h1>
          <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-ink/60 sm:text-base">
            Slow-cooked, richly spiced, and prepared according to timeless ancestral
            recipes. Order freshly made Nigerian delicacies delivered directly to your
            doorstep.
          </p>
        </div>
      </section>

      <div className="mx-auto max-w-7xl space-y-14 px-5 py-12 lg:px-8 lg:py-16">
        <MenuFilters
          query={query}
          onQueryChange={setQuery}
          category={category}
          onCategoryChange={setCategory}
          sort={sort}
          onSortChange={setSort}
          resultCount={filtered.length} />
        

        {error ?
        <div
          role="alert"
          className="flex flex-col items-center gap-4 rounded-2xl border border-red-200 bg-red-50 px-6 py-12 text-center">
          
            <AlertTriangleIcon className="h-10 w-10 text-red-600" />
            <div>
              <h2 className="font-display text-xl font-bold text-ink">
                We couldn't load the menu
              </h2>
              <p className="mt-1 text-sm text-ink/60">{error}</p>
            </div>
            <Button onClick={retry}>Try again</Button>
          </div> :
        isLoading ?
        <div>
            <span className="sr-only" role="status">
              Loading menu
            </span>
            <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {Array.from({ length: 8 }).map((_, index) =>
            <FoodCardSkeleton key={index} />
            )}
            </div>
          </div> :

        <>
            {isBrowsingAll && specials.length > 0 ?
          <MenuSection
            icon={<TagIcon className="h-4 w-4" />}
            eyebrow="Limited time"
            title="Today's Specials"
            description="Chef-picked dishes at a reduced price — available until the kitchen closes tonight."
            items={specials} /> :

          null}

            {isBrowsingAll && popular.length > 0 ?
          <MenuSection
            icon={<FlameIcon className="h-4 w-4" />}
            eyebrow="Most ordered"
            title="Popular Right Now"
            description="The best-selling plates our UK customers come back for week after week."
            items={popular} /> :

          null}

            {isBrowsingAll && newArrivals.length > 0 ?
          <MenuSection
            icon={<SparklesIcon className="h-4 w-4" />}
            eyebrow="Fresh on the menu"
            title="New Arrivals"
            description="Recently added recipes from our kitchen — be among the first to try them."
            items={newArrivals} /> :

          null}

            <section aria-labelledby="all-dishes">
              <SectionHeading
              eyebrow={isBrowsingAll ? 'The full spread' : 'Results'}
              title={isBrowsingAll ? 'Every Dish We Cook' : 'Matching Dishes'}
              description={
              isBrowsingAll ?
              'Browse the complete SoYummy kitchen, from party rice trays to chilled hibiscus zobo.' :
              undefined
              } />
            
              <h2 id="all-dishes" className="sr-only">
                All dishes
              </h2>

              {filtered.length === 0 ?
            <div className="mt-8 rounded-2xl border border-dashed border-ink/20 bg-white px-6 py-16 text-center">
                  <h3 className="font-display text-xl font-bold text-ink">
                    No dishes match your search
                  </h3>
                  <p className="mx-auto mt-2 max-w-sm text-sm text-ink/60">
                    Try a different dish name, or clear your filters to see the whole
                    menu.
                  </p>
                  <Button
                variant="outline"
                className="mt-5"
                onClick={() => {
                  setQuery('');
                  setCategory('all');
                  setSort('featured');
                }}>
                
                    Reset filters
                  </Button>
                </div> :

            <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                  {filtered.map((item) =>
              <FoodCard key={item.id} item={item} />
              )}
                </div>
            }
            </section>
          </>
        }
      </div>
    </div>);

}

interface MenuSectionProps {
  icon: React.ReactNode;
  eyebrow: string;
  title: string;
  description: string;
  items: MenuItem[];
}

function MenuSection({ icon, eyebrow, title, description, items }: MenuSectionProps) {
  return (
    <section aria-label={title}>
      <div className="flex items-center gap-2 text-brand-500">
        {icon}
        <span className="text-xs font-semibold uppercase tracking-[0.18em]">
          {eyebrow}
        </span>
      </div>
      <h2 className="mt-2 font-display text-3xl font-bold leading-tight text-ink sm:text-4xl">
        {title}
      </h2>
      <p className="mt-3 max-w-2xl text-sm leading-relaxed text-ink/60 sm:text-base">
        {description}
      </p>
      <div className="mt-8 grid gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {items.map((item) =>
        <FoodCard key={`${title}-${item.id}`} item={item} />
        )}
      </div>
    </section>);

}