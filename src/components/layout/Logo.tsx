import React from 'react';
import { cn } from '../../utils/cn';

interface LogoProps {
  className?: string;
  tone?: 'light' | 'dark';
}

export function Logo({ className, tone = 'light' }: LogoProps) {
  return (
    <span className={cn('inline-flex items-center gap-2', className)}>
      <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-brand-500 font-display text-sm font-bold text-white">
        S
      </span>
      <span
        className={cn(
          'font-display text-lg font-bold tracking-tight',
          tone === 'dark' ? 'text-white' : 'text-ink'
        )}>
        
        SoYummy <span className="text-brand-500">Foods</span>
      </span>
    </span>);

}