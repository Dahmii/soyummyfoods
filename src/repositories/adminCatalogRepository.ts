import { getSupabaseClient } from '../lib/supabase';
import type { AdminCategory, AdminProduct, AdminProductImage, CategoryInput, ProductImageInput, ProductInput } from '../types/catalog';

export const PRODUCT_IMAGE_BUCKET = 'product-images';
export const PRODUCT_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

const PRODUCT_IMAGE_TYPES = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp'
} as const;

function fail(error: { message: string } | null): void { if (error) throw new Error(error.message); }

function describeStorageError(error: { message: string } | null, fallback: string): string {
  return error?.message ? `${fallback} ${error.message}` : fallback;
}

export function resolveProductImageUrl(image: Pick<AdminProductImage, 'storage_bucket' | 'storage_path'>): string {
  if (image.storage_bucket === null) return image.storage_path;
  return getSupabaseClient().storage.from(PRODUCT_IMAGE_BUCKET).getPublicUrl(image.storage_path).data.publicUrl;
}

export function validateProductImageFile(file: File | null): { extension: 'jpg' | 'png' | 'webp'; file: File } {
  if (!file) throw new Error('Choose a JPEG, PNG, or WebP image to upload.');
  if (file.size <= 0) throw new Error('The selected image is empty. Choose a different file.');
  if (file.size > PRODUCT_IMAGE_MAX_BYTES) throw new Error('Image files must be 5 MiB or smaller.');
  const extension = PRODUCT_IMAGE_TYPES[file.type as keyof typeof PRODUCT_IMAGE_TYPES];
  if (!extension) throw new Error('Unsupported image type. Use JPEG, PNG, or WebP; HEIC is not supported yet.');
  return { file, extension };
}

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

export async function uploadProductImage(
  productId: string,
  file: File,
  input: Pick<ProductImageInput, 'alt_text' | 'display_order'>
): Promise<AdminProductImage> {
  const { extension } = validateProductImageFile(file);
  const objectPath = `products/${productId}/${crypto.randomUUID()}.${extension}`;
  const client = getSupabaseClient();
  const { error: uploadError } = await client.storage
    .from(PRODUCT_IMAGE_BUCKET)
    .upload(objectPath, file, { contentType: file.type, upsert: false });
  if (uploadError) throw new Error(describeStorageError(uploadError, 'Could not upload the image.'));

  let image: AdminProductImage;
  try {
    const { data, error } = await client.rpc('attach_admin_product_image', {
      p_product_id: productId,
      p_storage_bucket: PRODUCT_IMAGE_BUCKET,
      p_storage_path: objectPath,
      p_alt_text: input.alt_text,
      p_display_order: input.display_order
    }).single();
    fail(error);
    image = data as AdminProductImage;
  } catch (cause) {
    const { error: cleanupError } = await client.storage.from(PRODUCT_IMAGE_BUCKET).remove([objectPath]);
    const message = cause instanceof Error ? cause.message : 'Could not attach the uploaded image to the product.';
    if (cleanupError) throw new Error(`${message} The uploaded file could not be cleaned up automatically.`);
    throw new Error(message);
  }
  return image;
}

export async function removeProductImage(image: AdminProductImage): Promise<{ cleanupWarning: string | null }> {
  await deleteProductImage(image.id);
  if (image.storage_bucket === null) return { cleanupWarning: null };
  const { error } = await getSupabaseClient().storage.from(PRODUCT_IMAGE_BUCKET).remove([image.storage_path]);
  return { cleanupWarning: error ? 'The image reference was removed, but the uploaded file could not be cleaned up automatically.' : null };
}
