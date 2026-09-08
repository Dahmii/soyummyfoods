import React from 'react';
import { SearchIcon, XIcon } from 'lucide-react';
import { Input } from '../ui/input';
import { Select } from '../ui/select';
import { SORT_OPTIONS, type MenuCategoryOption, type SortOption } from '../../types/menu';
import { cn } from '../../utils/cn';

export type CategoryFilter = string | 'all';

interface MenuFiltersProps {
  query: string;
  onQueryChange: (value: string) => void;
  category: CategoryFilter;
  onCategoryChange: (value: CategoryFilter) => void;
  sort: SortOption;
  onSortChange: (value: SortOption) => void;
  resultCount: number;
  categories: MenuCategoryOption[];
}

export function MenuFilters({
  query,
  onQueryChange,
  category,
  onCategoryChange,
  sort,
  onSortChange,
  resultCount,
  categories
}: MenuFiltersProps) {
  const categoryFilters = [{ slug: 'all', name: 'All Dishes' }, ...categories];

  return (
    <section
      aria-label="Menu filters"
      className="rounded-2xl border border-ink/10 bg-white p-4 shadow-card sm:p-5">
      
      <div className="flex flex-col gap-3 lg:flex-row lg:items-center">
        <div className="relative flex-1">
          <SearchIcon
            className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/40"
            aria-hidden="true" />
          
          <label htmlFor="menu-search" className="sr-only">
            Search dishes
          </label>
          <Input
            id="menu-search"
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search dishes — try “jollof”, “suya”, “zobo”…"
            className="pl-10 pr-10" />
          
          {query ?
          <button
            type="button"
            onClick={() => onQueryChange('')}
            aria-label="Clear search"
            className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-ink/50 transition-colors hover:bg-ink/5 hover:text-ink">
            
              <XIcon className="h-4 w-4" />
            </button> :
          null}
        </div>

        <div className="w-full lg:w-56">
          <label htmlFor="menu-sort" className="sr-only">
            Sort dishes
          </label>
          <Select
            id="menu-sort"
            value={sort}
            options={SORT_OPTIONS.map((option) => ({ ...option }))}
            onChange={(event) => onSortChange(event.target.value as SortOption)} />
          
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {categoryFilters.map((entry) => {
          const value = entry.slug;
          const isActive = category === value;
          return (
            <button
              key={value}
              type="button"
              onClick={() => onCategoryChange(value)}
              aria-pressed={isActive}
              className={cn(
                'rounded-full border px-4 py-2 text-sm font-medium transition-colors',
                isActive ?
                'border-brand-500 bg-brand-500 text-white' :
                'border-ink/10 bg-white text-ink/70 hover:border-brand-300 hover:text-brand-600'
              )}>
              
              {entry.name}
            </button>);

        })}
      </div>

      <p className="mt-4 text-xs font-medium uppercase tracking-[0.12em] text-ink/50">
        {resultCount} {resultCount === 1 ? 'dish' : 'dishes'} shown
      </p>
    </section>);

}
