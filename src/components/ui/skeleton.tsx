import React from 'react';
import { cn } from '../../utils/cn';

export function Skeleton({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('animate-pulse rounded-xl bg-ink/10', className)}
      aria-hidden="true"
      {...props} />);


}