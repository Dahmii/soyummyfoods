import React from 'react';
import { Link } from 'react-router-dom';
import { AlertTriangleIcon } from 'lucide-react';
import { cn } from '../utils/cn';

interface AllergyNoticeProps {
  className?: string;
}

export function AllergyNotice({ className }: AllergyNoticeProps) {
  return (
    <aside
      className={cn(
        'flex flex-col gap-3 rounded-2xl border border-ink/10 bg-white px-5 py-4 sm:flex-row sm:items-center sm:justify-between',
        className
      )}>
      
      <p className="flex items-start gap-3 text-sm leading-relaxed text-ink/70">
        <AlertTriangleIcon className="mt-0.5 h-4 w-4 shrink-0 text-brand-500" />
        <span>
          <span className="font-semibold text-ink">Allergy advisory:</span> our kitchen
          handles gluten, fish, crustaceans, soybeans, nuts, seeds and eggs. We cannot
          guarantee any dish is free of cross-contamination.
        </span>
      </p>
      <Link
        to="/allergy"
        className="shrink-0 text-sm font-semibold text-brand-600 underline-offset-4 transition-colors hover:text-brand-700 hover:underline">
        
        Read the full notice
      </Link>
    </aside>);

}