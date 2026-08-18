import React from 'react';
import { cn } from '../../utils/cn';

export type CardProps = React.HTMLAttributes<HTMLDivElement>;

export const Card = React.forwardRef<HTMLDivElement, CardProps>(
  ({ className, ...props }, ref) =>
  <div
    ref={ref}
    className={cn(
      'overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card',
      className
    )}
    {...props} />


);
Card.displayName = 'Card';

export function CardContent({ className, ...props }: CardProps) {
  return <div className={cn('p-5', className)} {...props} />;
}

export function CardFooter({ className, ...props }: CardProps) {
  return (
    <div
      className={cn(
        'flex items-center justify-between border-t border-ink/10 p-5',
        className
      )}
      {...props} />);


}