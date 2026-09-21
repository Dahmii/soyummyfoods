import { getSupabaseClient } from '../lib/supabase';
import {
  menuCategoryOptionSchema,
  menuResponseSchema,
  type MenuCatalog } from
'../types/menu';
import { PRODUCT_IMAGE_BUCKET } from './adminCatalogRepository';

interface CategoryRow {
  slug: string;
  name: string;
  display_order: number;
}

interface ProductImageRow {
  storage_path: string;
  storage_bucket: string | null;
  alt_text: string | null;
  is_primary: boolean;
  display_order: number;
}

interface ProductSellabilityRow {
  product_id: string;
  is_orderable: boolean;
}

interface ProductRow {
  id: string;
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
  const [categoriesResponse, productsResponse, sellabilityResponse] = await Promise.all([
    supabase
      .from('categories')
      .select('slug, name, display_order')
      .eq('is_active', true)
      .order('display_order')
      .abortSignal(requestSignal),
    supabase
      .from('products')
      .select(
        'id, slug, name, description, base_price, sale_price, price_on_request, portion_note, prep_time_minutes, is_available, tags, category:categories!inner(slug), images:product_images(storage_path, storage_bucket, alt_text, is_primary, display_order)'
      )
      .eq('status', 'active')
      .order('display_order')
      .abortSignal(requestSignal),
    supabase
      .rpc('get_public_product_sellability')
      .abortSignal(requestSignal)
  ]);

  const { data: categories, error: categoriesError } = categoriesResponse;
  const { data, error } = productsResponse;
  const { data: sellability, error: sellabilityError } = sellabilityResponse;

  if (categoriesError) throw new Error('The menu could not be loaded right now.');
  if (error || sellabilityError) throw new Error('The menu could not be loaded right now.');
  const categoryData = menuCategoryOptionSchema.array().safeParse(
    ((categories ?? []) as unknown as CategoryRow[]).map((category) => ({
      slug: category.slug,
      name: category.name,
      displayOrder: category.display_order
    }))
  );
  if (!categoryData.success) throw new Error('The menu could not be loaded right now.');
  const activeCategorySlugs = new Set(categoryData.data.map((category) => category.slug));

  const sellabilityByProductId = new Map(
    ((sellability ?? []) as unknown as ProductSellabilityRow[]).map((item) => [item.product_id, item.is_orderable])
  );

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
        databaseId: product.id,
        name: product.name,
        description: product.description,
        price: product.base_price === null ? null : Number(product.base_price),
        image: primaryImage.storage_bucket === null
          ? primaryImage.storage_path
          : supabase.storage.from(PRODUCT_IMAGE_BUCKET).getPublicUrl(primaryImage.storage_path).data.publicUrl,
        imageAlt: primaryImage.alt_text?.trim() || product.name,
        category: product.category.slug,
        prepTimeMinutes: product.prep_time_minutes,
        // Price-on-request items retain their existing enquiry-only path. Every
        // normal cart item fails closed when its sellability row is missing.
        available: product.price_on_request
          ? product.is_available
          : sellabilityByProductId.get(product.id) ?? false,
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
