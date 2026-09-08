import { getSupabaseClient } from '../lib/supabase';
import type { AdminCategory, AdminProduct, AdminProductImage, CategoryInput, ProductImageInput, ProductInput } from '../types/catalog';

function fail(error: { message: string } | null): void { if (error) throw new Error(error.message); }

export async function listAdminCategories(): Promise<AdminCategory[]> {
  const { data, error } = await getSupabaseClient().from('categories').select('*').order('display_order');
  fail(error); return (data ?? []) as AdminCategory[];
}
export async function saveCategory(input: CategoryInput, id?: string): Promise<void> {
  const client = getSupabaseClient();
  const result = id ? await client.from('categories').update(input).eq('id', id) : await client.from('categories').insert(input);
  fail(result.error);
}
export async function listAdminProducts(): Promise<AdminProduct[]> {
  const { data, error } = await getSupabaseClient().from('products').select('*, category:categories(name, slug)').order('display_order');
  fail(error); return (data ?? []) as AdminProduct[];
}
export async function getAdminProduct(id: string): Promise<AdminProduct> {
  const { data, error } = await getSupabaseClient().from('products').select('*, category:categories(name, slug)').eq('id', id).single();
  fail(error); return data as AdminProduct;
}
export async function saveProduct(input: ProductInput, id?: string): Promise<string> {
  const client = getSupabaseClient();
  if (id) { const { error } = await client.from('products').update(input).eq('id', id); fail(error); return id; }
  const { data, error } = await client.from('products').insert(input).select('id').single(); fail(error); return data.id as string;
}
export async function listProductImages(productId: string): Promise<AdminProductImage[]> {
  const { data, error } = await getSupabaseClient().from('product_images').select('*').eq('product_id', productId).order('display_order');
  fail(error); return (data ?? []) as AdminProductImage[];
}
export async function saveProductImage(productId: string, input: ProductImageInput, id?: string): Promise<void> {
  const client = getSupabaseClient();
  const result = id ? await client.from('product_images').update(input).eq('id', id) : await client.from('product_images').insert({ ...input, product_id: productId, is_primary: false });
  fail(result.error);
}
export async function deleteProductImage(id: string): Promise<void> { const { error } = await getSupabaseClient().from('product_images').delete().eq('id', id); fail(error); }
export async function setPrimaryImage(productId: string, imageId: string): Promise<void> { const { error } = await getSupabaseClient().rpc('set_product_primary_image', { target_product_id: productId, target_image_id: imageId }); fail(error); }
