import React from 'react';
import { cn } from '../utils/cn';

interface SectionHeadingProps {
  eyebrow?: string;
  title: string;
  description?: string;
  align?: 'left' | 'center';
  tone?: 'light' | 'dark';
  className?: string;
}

export function SectionHeading({
  eyebrow,
  title,
  description,
  align = 'left',
  tone = 'light',
  className
}: SectionHeadingProps) {
  return (
    <div
      className={cn(
        'max-w-2xl',
        align === 'center' && 'mx-auto text-center',
        className
      )}>
      
      {eyebrow ?
      <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">
          {eyebrow}
        </p> :
      null}
      <h2
        className={cn(
          'mt-2 font-display text-3xl font-bold leading-tight sm:text-4xl',
          tone === 'dark' ? 'text-white' : 'text-ink'
        )}>
        
        {title}
      </h2>
      {description ?
      <p
        className={cn(
          'mt-3 text-sm leading-relaxed sm:text-base',
          tone === 'dark' ? 'text-white/70' : 'text-ink/60'
        )}>
        
          {description}
        </p> :
      null}
    </div>);

}