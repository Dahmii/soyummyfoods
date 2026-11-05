import React, { useEffect, useRef } from 'react';

interface FsaRatingBadgeProps {
  businessId: string;
  ratingStyle?: '1' | '2' | '3' | '4';
  welsh?: boolean;
}

export function FsaRatingBadge({
  businessId,
  ratingStyle = '1',
  welsh = false,
}: FsaRatingBadgeProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Clear any previously injected content on re-renders
    container.innerHTML = '';

    // Create and configure script tag using vanilla DOM API so the browser executes it
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