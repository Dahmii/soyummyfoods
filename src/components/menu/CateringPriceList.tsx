import React from 'react';
import { MessageCircleIcon, Plus } from 'lucide-react';
import { Button } from '../ui/button';
import {
  CATERING_RICE_AND_SIDES,
  CATERING_SOUPS_AND_PROTEINS,
  SOUP_BOWLS,
  SOUP_BOWL_PRICE,
  type CateringRow,
} from '../../data/catering';
import {
  buildCateringEnquiryMessage,
  openWhatsApp,
} from '../../utils/whatsapp';
import { useCartStore } from '../../hooks/useCartStore';
import { effectivePrice, type MenuItem } from '../../types/menu';

interface CateringPriceListProps {
  menuItems: MenuItem[];
}

const SOUP_BOWL_UNIT_PRICE = 20;

const SOUP_PRODUCT_SLUGS: Record<string, string> = {
  'Efo-riro': 'efo-riro-1-litre-bowl',
  'Egusi': 'egusi-1-litre-bowl',
  'Assorted Meat (Buka) Stew': 'assorted-meat-buka-stew-1-litre-bowl',
  'Ofada Stew / Sauce': 'ofada-stew-sauce-1-litre-bowl',
  'Goat Meat Stew': 'goat-meat-stew-1-litre-bowl',
  'Mixed Okra': 'mixed-okra-1-litre-bowl',
  'Gbegiri': 'gbegiri-1-litre-bowl',
  'Ewedu': 'ewedu-1-litre-bowl',
};

export function CateringPriceList({ menuItems }: CateringPriceListProps) {
  const addItem = useCartStore((state) => state.addItem);
  const openCart = useCartStore((state) => state.openCart);

  const findSoupProduct = (soup: string) => {
    const slug = SOUP_PRODUCT_SLUGS[soup];

    if (!slug) return undefined;

    return menuItems.find(
      (item) =>
        item.id === slug &&
        item.available &&
        Boolean(item.databaseId) &&
        effectivePrice(item) === SOUP_BOWL_UNIT_PRICE
    );
  };

  const handleAddSoupToCart = (soup: string) => {
    const product = findSoupProduct(soup);

    if (!product) return;

    addItem(product);
    openCart();
  };

  return (
    <section aria-labelledby="bulk-catering" className="space-y-8">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div className="max-w-2xl">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-500">
            Weddings, birthdays & corporate events
          </p>

          <h2
            id="bulk-catering"
            className="mt-2 font-display text-3xl font-bold leading-tight text-ink sm:text-4xl"
          >
            Bulk Catering Orders
          </h2>

          <p className="mt-3 text-sm leading-relaxed text-ink/60 sm:text-base">
            Trays and coolers are quoted per portion size and confirmed with our
            kitchen. Send us your headcount on WhatsApp and we'll build the menu with
            you.
          </p>
        </div>

        <Button
          size="lg"
          className="shrink-0 bg-[#25D366] hover:bg-[#1EBE57]"
          onClick={() => openWhatsApp(buildCateringEnquiryMessage())}
        >
          <MessageCircleIcon className="h-4 w-4" />
          Request a catering quote
        </Button>
      </div>

      {/* 1 Litre Soup Bowls */}
      <div className="rounded-2xl border border-brand-100 bg-brand-50 p-5 sm:p-6">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h3 className="font-display text-xl font-bold text-ink">
            1 Litre Soup Bowls
          </h3>

          <span className="font-display text-xl font-bold text-brand-600">
            {SOUP_BOWL_PRICE}
          </span>
        </div>

        <p className="mt-2 text-sm text-ink/60">
          Select a soup to add it to your basket.
        </p>

        <ul className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {SOUP_BOWLS.map((soup) => {
            const product = findSoupProduct(soup);
            const isAvailable = Boolean(product);

            return (
              <li key={soup}>
                <button
                  type="button"
                  disabled={!isAvailable}
                  onClick={() => handleAddSoupToCart(soup)}
                  className="group flex w-full items-center gap-2 rounded-xl border border-brand-100 bg-white p-3 text-left text-sm font-medium text-ink transition-all hover:border-brand-400 hover:bg-brand-50 hover:shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-brand-100 disabled:hover:bg-white disabled:hover:shadow-none"
                  aria-label={
                    isAvailable
                      ? `Add ${soup}, 1 litre soup bowl, to basket`
                      : `${soup} is not currently available as a 1 litre soup bowl`
                  }
                >
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-brand-100 text-brand-600 transition-colors group-hover:bg-brand-500 group-hover:text-white">
                    <Plus className="h-3.5 w-3.5" />
                  </span>

                  <span>{soup}</span>
                </button>
              </li>
            );
          })}
        </ul>

        <p className="mt-4 text-xs text-ink/50">
          Each bowl contains 1 litre. Add your preferred soup to your basket.
        </p>
      </div>

      <div className="grid gap-6 xl:grid-cols-2">
        <CateringTable
          title="Rice, Sides & Small Chops"
          rows={CATERING_RICE_AND_SIDES}
        />

        <CateringTable
          title="Soups, Stews & Proteins"
          rows={CATERING_SOUPS_AND_PROTEINS}
        />
      </div>
    </section>
  );
}

interface CateringTableProps {
  title: string;
  rows: CateringRow[];
}

function CateringTable({ title, rows }: CateringTableProps) {
  return (
    <div className="overflow-hidden rounded-2xl border border-ink/10 bg-white shadow-card">
      <h3 className="border-b border-ink/10 px-5 py-4 font-display text-lg font-bold text-ink">
        {title}
      </h3>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[32rem] border-collapse text-left text-sm">
          <caption className="sr-only">
            {title} bulk catering price list
          </caption>

          <thead>
            <tr className="bg-ink text-white">
              <th scope="col" className="px-5 py-3 font-semibold">
                Meal / Item
              </th>

              <th scope="col" className="px-4 py-3 font-semibold">
                ½ Tray
              </th>

              <th scope="col" className="px-4 py-3 font-semibold">
                1 Tray
              </th>

              <th scope="col" className="px-5 py-3 font-semibold">
                1 Cooler
              </th>
            </tr>
          </thead>

          <tbody>
            {rows.map((row, index) => (
              <tr
                key={row.item}
                className={index % 2 === 1 ? 'bg-cream' : 'bg-white'}
              >
                <th scope="row" className="px-5 py-3 font-semibold text-ink">
                  {row.item}

                  {row.note ? (
                    <span className="block text-xs font-normal italic text-ink/50">
                      {row.note}
                    </span>
                  ) : null}
                </th>

                <td className="px-4 py-3 text-ink/70">
                  {row.halfTray}
                </td>

                <td className="px-4 py-3 text-ink/70">
                  {row.fullTray}
                </td>

                <td className="px-5 py-3 text-ink/70">
                  {row.cooler}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="border-t border-ink/10 px-5 py-3">
        <button
          type="button"
          onClick={() => openWhatsApp(buildCateringEnquiryMessage(title))}
          className="text-sm font-semibold text-brand-600 transition-colors hover:text-brand-700"
        >
          Order this section on WhatsApp →
        </button>
      </div>
    </div>
  );
}