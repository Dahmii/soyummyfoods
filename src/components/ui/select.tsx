import React from 'react';
import { ChevronDownIcon } from 'lucide-react';
import { cn } from '../../utils/cn';

export interface SelectProps extends
  React.SelectHTMLAttributes<HTMLSelectElement> {
  options: ReadonlyArray<{value: string;label: string;}>;
}

export const Select = React.forwardRef<HTMLSelectElement, SelectProps>(
  ({ className, options, ...props }, ref) =>
  <div className="relative">
      <select
      ref={ref}
      className={cn(
        'h-11 w-full appearance-none rounded-full border border-ink/10 bg-white pl-4 pr-10 text-sm font-medium text-ink shadow-sm transition-colors focus-visible:border-brand-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500/25',
        className
      )}
      {...props}>
      
        {options.map((option) =>
      <option key={option.value} value={option.value}>
            {option.label}
          </option>
      )}
      </select>
      <ChevronDownIcon
      className="pointer-events-none absolute right-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-ink/50"
      aria-hidden="true" />
    
    </div>

);
Select.displayName = 'Select';