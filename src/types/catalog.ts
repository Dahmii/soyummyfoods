import { z } from 'zod';

export const CATALOG_TAGS = ['popular', 'new', 'special'] as const;
export const PRODUCT_STATUSES = ['draft', 'active', 'archived'] as const;

const localImagePath = /^\/[A-Za-z0-9][A-Za-z0-9._/-]*\.(jpg|jpeg|png|webp)$/i;
const nullableMoney = z.number().nonnegative().nullable();

export const categoryInputSchema = z.object({
  name: z.string().trim().min(1),
  slug: z.string().trim().min(1),
  description: z.string().trim().nullable(),
  is_active: z.boolean(),
  display_order: z.number().int().nonnegative()
});

export const productInputSchema = z.object({
  category_id: z.string().uuid(),
  slug: z.string().trim().min(1),
  name: z.string().trim().min(1),
  description: z.string().trim().min(1),
  base_price: nullableMoney,
  sale_price: nullableMoney,
  price_on_request: z.boolean(),
  portion_note: z.string().trim().nullable(),
  prep_time_minutes: z.number().int().positive(),
  status: z.enum(PRODUCT_STATUSES),
  is_available: z.boolean(),
  tags: z.array(z.enum(CATALOG_TAGS)),
  display_order: z.number().int().nonnegative()
}).superRefine((value, context) => {
  if (value.price_on_request && (value.base_price !== null || value.sale_price !== null)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Price on request cannot have prices.' });
  }
  if (!value.price_on_request && value.base_price === null) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Base price is required.' });
  }
  if (value.sale_price !== null && value.base_price !== null && value.sale_price > value.base_price) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Sale price cannot exceed base price.' });
  }
});

export const productImageInputSchema = z.object({
  storage_path: z.string().regex(localImagePath, 'Use an approved root-relative local image path.'),
  alt_text: z.string().trim().nullable(),
  display_order: z.number().int().nonnegative()
});

export type CategoryInput = z.infer<typeof categoryInputSchema>;
export type ProductInput = z.infer<typeof productInputSchema>;
export type ProductImageInput = z.infer<typeof productImageInputSchema>;

export interface AdminCategory extends CategoryInput { id: string; created_at: string; }
export interface AdminProduct extends ProductInput { id: string; created_at: string; category: { name: string; slug: string; } | null; }
export interface AdminProductImage { id: string; product_id: string; storage_path: string; alt_text: string | null; is_primary: boolean; display_order: number; }
