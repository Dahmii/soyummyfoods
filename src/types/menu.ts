import { z } from 'zod';

export const menuCategorySchema = z.enum([
'rice-dishes',
'beans-dishes',
'yam-dishes',
'starters-sides',
'pepper-soups',
'soups-stews',
'proteins']
);

export type MenuCategory = z.infer<typeof menuCategorySchema>;

export const menuItemSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  description: z.string().min(1),
  price: z.number().nonnegative(),
  image: z.string().min(1),
  category: menuCategorySchema,
  prepTimeMinutes: z.number().int().positive(),
  available: z.boolean(),
  tags: z.array(z.enum(['popular', 'new', 'special'])).default([]),
  rating: z.number().min(0).max(5),
  specialPrice: z.number().positive().optional(),
  /** Items quoted by the kitchen — no fixed online price. */
  priceOnRequest: z.boolean().optional(),
  /** Portion note shown under the price, e.g. "5 pcs" or "1 litre bowl". */
  portion: z.string().optional()
});

export type MenuItem = z.infer<typeof menuItemSchema>;

export const menuResponseSchema = z.array(menuItemSchema);

export const CATEGORY_LABELS: Record<MenuCategory, string> = {
  'rice-dishes': 'Rice Dishes',
  'beans-dishes': 'Beans Dishes',
  'yam-dishes': 'Yam Dishes',
  'starters-sides': 'Starters & Sides',
  'pepper-soups': 'Pepper Soups',
  'soups-stews': 'Soups & Stews',
  proteins: 'Proteins'
};

export const SORT_OPTIONS = [
{ value: 'featured', label: 'Featured' },
{ value: 'price-asc', label: 'Price: Low to High' },
{ value: 'price-desc', label: 'Price: High to Low' },
{ value: 'prep-time', label: 'Fastest to Prepare' }] as
const;

export type SortOption = (typeof SORT_OPTIONS)[number]['value'];

export function effectivePrice(item: MenuItem): number {
  return item.specialPrice ?? item.price;
}