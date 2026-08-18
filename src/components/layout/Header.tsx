import React, { useState } from 'react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { MenuIcon, XIcon } from 'lucide-react';
import { Button } from '../ui/button';
import { Logo } from './Logo';
import { cn } from '../../utils/cn';

const NAV_LINKS = [
{ to: '/', label: 'Home' },
{ to: '/menu', label: 'Menu' },
{ to: '/media', label: 'Media' },
{ to: '/blog', label: 'Blog' }];


export function Header() {
  const [open, setOpen] = useState(false);
  const location = useLocation();

  return (
    <header className="sticky top-0 z-40 border-b border-ink/10 bg-white/90 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 lg:px-8">
        <Link to="/" aria-label="SoYummy Foods home">
          <Logo />
        </Link>

        <nav aria-label="Main" className="hidden items-center gap-8 md:flex">
          {NAV_LINKS.map((link) =>
          <NavLink
            key={link.to}
            to={link.to}
            className={({ isActive }) =>
            cn(
              'text-sm font-medium transition-colors hover:text-brand-500',
              isActive ? 'text-brand-500' : 'text-ink/70'
            )
            }>
            
              {link.label}
            </NavLink>
          )}
        </nav>

        <div className="flex items-center gap-2">
          <Button asChild size="sm" className="hidden sm:inline-flex">
            <Link to="/menu">Order Online</Link>
          </Button>
          <button
            type="button"
            onClick={() => setOpen((value) => !value)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-full text-ink transition-colors hover:bg-ink/5 md:hidden"
            aria-expanded={open}
            aria-label={open ? 'Close navigation' : 'Open navigation'}>
            
            {open ? <XIcon className="h-5 w-5" /> : <MenuIcon className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {open ?
      <nav
        aria-label="Mobile"
        className="border-t border-ink/10 bg-white px-5 py-3 md:hidden">
        
          <ul className="space-y-1">
            {NAV_LINKS.map((link) =>
          <li key={link.to}>
                <Link
              to={link.to}
              onClick={() => setOpen(false)}
              className={cn(
                'block rounded-xl px-3 py-2.5 text-sm font-medium transition-colors',
                location.pathname === link.to ?
                'bg-brand-50 text-brand-700' :
                'text-ink/75 hover:bg-ink/5'
              )}>
              
                  {link.label}
                </Link>
              </li>
          )}
            <li className="pt-2">
              <Button asChild className="w-full" onClick={() => setOpen(false)}>
                <Link to="/menu">Order Online</Link>
              </Button>
            </li>
          </ul>
        </nav> :
      null}
    </header>);

}