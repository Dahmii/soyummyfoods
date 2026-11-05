import React, { useEffect, useRef, useState } from 'react';

interface FsaRatingBadgeProps {
  businessId: string;
  welsh?: boolean;
}

export function FsaRatingBadge({ businessId, welsh = false }: FsaRatingBadgeProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isMobile, setIsMobile] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return window.innerWidth < 640; // matches Tailwind's 'sm' breakpoint
  });

  useEffect(() => {
    const mediaQuery = window.matchMedia('(max-width: 639px)');
    const handleMediaQueryChange = (e: MediaQueryListEvent) => {
      setIsMobile(e.matches);
    };

    mediaQuery.addEventListener('change', handleMediaQueryChange);
    return () => mediaQuery.removeEventListener('change', handleMediaQueryChange);
  }, []);

  const ratingStyle = isMobile ? '3' : '1';

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Reset container contents
    container.innerHTML = '';

    // Create and configure script
    const script = document.createElement('script');
    script.src = 'https://ratings.food.gov.uk/embed/embed-badge.js';
    script.async = true;
    script.setAttribute('data-business-id', businessId);
    script.setAttribute('data-rating-style', ratingStyle);
    script.setAttribute('data-welsh', String(welsh));

    container.appendChild(script);

    return () => {
      container.innerHTML = '';
    };
  }, [businessId, ratingStyle, welsh]);

  return (
    <div
      ref={containerRef}
      className="flex min-h-[90px] items-center justify-center overflow-hidden py-2"
    />
  );
}