import { z } from 'zod';

export const menuCategorySchema = z.string().trim().min(1);

export type MenuCategory = z.infer<typeof menuCategorySchema>;

export const menuItemSchema = z.object({
  id: z.string().min(1),
  databaseId: z.string().uuid().optional(),
  name: z.string().min(1),
  description: z.string().min(1),
  price: z.number().nonnegative().nullable(),
  image: z.string().min(1),
  category: menuCategorySchema,
  prepTimeMinutes: z.number().int().positive(),
  available: z.boolean(),
  tags: z.array(z.enum(['popular', 'new', 'special'])).default([]),
  rating: z.number().min(0).max(5).nullable().optional(),
  specialPrice: z.number().positive().optional(),
  /** Items quoted by the kitchen — no fixed online price. */
  priceOnRequest: z.boolean().optional(),
  /** Portion note shown under the price, e.g. "5 pcs" or "1 litre bowl". */
  portion: z.string().optional()
});

export type MenuItem = z.infer<typeof menuItemSchema>;

export const menuResponseSchema = z.array(menuItemSchema);

export const menuCategoryOptionSchema = z.object({
  slug: menuCategorySchema,
  name: z.string().trim().min(1),
  displayOrder: z.number().int().nonnegative()
});

export type MenuCategoryOption = z.infer<typeof menuCategoryOptionSchema>;

export interface MenuCatalog {
  items: MenuItem[];
  categories: MenuCategoryOption[];
}

export const SORT_OPTIONS = [
{ value: 'featured', label: 'Featured' },
{ value: 'price-asc', label: 'Price: Low to High' },
{ value: 'price-desc', label: 'Price: High to Low' },
{ value: 'prep-time', label: 'Fastest to Prepare' }] as
const;

export type SortOption = (typeof SORT_OPTIONS)[number]['value'];

export function effectivePrice(item: MenuItem): number | null {
  return item.specialPrice ?? item.price;
}
