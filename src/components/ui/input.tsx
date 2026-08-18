import React from 'react';
import { cn } from '../../utils/cn';

export type InputProps = React.InputHTMLAttributes<HTMLInputElement>;

export const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type = 'text', ...props }, ref) =>
  <input
    ref={ref}
    type={type}
    className={cn(
      'flex h-11 w-full rounded-full border border-ink/10 bg-white px-4 text-sm text-ink shadow-sm transition-colors placeholder:text-ink/40 focus-visible:border-brand-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500/25 disabled:cursor-not-allowed disabled:opacity-50',
      className
    )}
    {...props} />


);
Input.displayName = 'Input';

export type TextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement>;

export const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, ...props }, ref) =>
  <textarea
    ref={ref}
    className={cn(
      'flex min-h-[92px] w-full rounded-2xl border border-ink/10 bg-white px-4 py-3 text-sm text-ink shadow-sm transition-colors placeholder:text-ink/40 focus-visible:border-brand-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500/25',
      className
    )}
    {...props} />


);
Textarea.displayName = 'Textarea';

export interface FieldProps {
  label: string;
  htmlFor: string;
  error?: string;
  children: React.ReactNode;
  className?: string;
}

export function Field({ label, htmlFor, error, children, className }: FieldProps) {
  return (
    <div className={cn('space-y-1.5', className)}>
      <label
        htmlFor={htmlFor}
        className="block text-xs font-semibold uppercase tracking-[0.12em] text-ink/60">
        
        {label}
      </label>
      {children}
      {error ?
      <p role="alert" className="text-xs font-medium text-red-600">
          {error}
        </p> :
      null}
    </div>);

}