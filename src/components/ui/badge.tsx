import React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '../../utils/cn';

const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.08em]',
  {
    variants: {
      variant: {
        default: 'bg-brand-500 text-white',
        dark: 'bg-ink/80 text-white backdrop-blur',
        soft: 'bg-brand-50 text-brand-700',
        outline: 'border border-ink/20 text-ink/70',
        success: 'bg-emerald-50 text-emerald-700',
        muted: 'bg-ink/10 text-ink/60'
      }
    },
    defaultVariants: { variant: 'default' }
  }
);

export interface BadgeProps extends
  React.HTMLAttributes<HTMLSpanElement>,
  VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}