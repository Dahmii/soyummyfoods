import React from 'react';
import { cn } from '../../utils/cn';

interface LogoProps {
  className?: string;
  tone?: 'light' | 'dark';
}

export function Logo({ className }: LogoProps) {
  return (
    <img
      src="/soyummy-logo.png"
      alt="SoYummy Foods"
      className={cn(
        'h-10 w-auto object-contain',
        className
      )}
    />
  );
}