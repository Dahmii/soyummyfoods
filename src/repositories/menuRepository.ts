import { getSupabaseClient } from '../lib/supabase';
import {
  menuCategoryOptionSchema,
  menuResponseSchema,
  type MenuCatalog } from
'../types/menu';

interface CategoryRow {
  slug: string;
  name: string;
  display_order: number;
}

interface ProductImageRow {
  storage_path: string;
  is_primary: boolean;
  display_order: number;
}

interface ProductRow {
  slug: string;
  name: string;
  description: string;
  base_price: number | string | null;
  sale_price: number | string | null;
  price_on_request: boolean;
  portion_note: string | null;
  prep_time_minutes: number;
  is_available: boolean;
  tags: string[];
  category: CategoryRow;
  images: ProductImageRow[];
}

export async function fetchMenuFromSupabase(
  signal: AbortSignal | undefined,
  ratingsBySlug: Readonly<Record<string, number>>
): Promise<MenuCatalog> {
  const supabase = getSupabaseClient();
  const requestSignal = signal ?? new AbortController().signal;
  const { data: categories, error: categoriesError } = await supabase
    .from('categories')
    .select('slug, name, display_order')
    .eq('is_active', true)
    .order('display_order')
    .abortSignal(requestSignal);

  if (categoriesError) throw new Error('The menu could not be loaded right now.');
  const categoryData = menuCategoryOptionSchema.array().safeParse(
    ((categories ?? []) as unknown as CategoryRow[]).map((category) => ({
      slug: category.slug,
      name: category.name,
      displayOrder: category.display_order
    }))
  );
  if (!categoryData.success) throw new Error('The menu could not be loaded right now.');
  const activeCategorySlugs = new Set(categoryData.data.map((category) => category.slug));

  const { data, error } = await supabase
    .from('products')
    .select(
      'slug, name, description, base_price, sale_price, price_on_request, portion_note, prep_time_minutes, is_available, tags, category:categories!inner(slug), images:product_images(storage_path, is_primary, display_order)'
    )
    .eq('status', 'active')
    .order('display_order')
    .abortSignal(requestSignal);

  if (error) throw new Error('The menu could not be loaded right now.');

  const mapped = ((data ?? []) as unknown as ProductRow[])
    .filter((product) => activeCategorySlugs.has(product.category.slug))
    .map((product) => {
      const primaryImage = product.images
        .filter((image) => image.is_primary)
        .sort((a, b) => a.display_order - b.display_order)[0];

      if (!primaryImage) {
        throw new Error(`The menu item "${product.slug}" has no primary image.`);
      }

      return {
        id: product.slug,
        name: product.name,
        description: product.description,
        price: product.base_price === null ? null : Number(product.base_price),
        image: primaryImage.storage_path,
        category: product.category.slug,
        prepTimeMinutes: product.prep_time_minutes,
        available: product.is_available,
        tags: product.tags,
        // Ratings remain frontend presentation metadata; they are not database data.
        rating: ratingsBySlug[product.slug],
        specialPrice: product.sale_price === null ? undefined : Number(product.sale_price),
        priceOnRequest: product.price_on_request || undefined,
        portion: product.portion_note ?? undefined
      };
    });

  const parsed = menuResponseSchema.safeParse(mapped);
  if (!parsed.success) throw new Error('The menu could not be loaded right now.');
  return { items: parsed.data, categories: categoryData.data };
}
