import { z } from 'zod';

const nullableText = z.string().trim().nullable();
const nullableEmail = z.string().trim().email('Enter a valid email address.').nullable();
const requiredNonnegativeNumber = (label: string) => z.number({ invalid_type_error: `${label} is required.` }).finite(`${label} must be a number.`).nonnegative(`${label} must be zero or greater.`);
const requiredNonnegativeInteger = (label: string) => requiredNonnegativeNumber(label).int(`${label} must be a whole number.`);

export const businessSettingsInputSchema = z.object({
  business_name: z.string().trim().min(1, 'Business name is required.'),
  legal_name: nullableText,
  email: nullableEmail,
  phone: nullableText,
  whatsapp_number: nullableText,
  address_line_1: nullableText,
  address_line_2: nullableText,
  city: nullableText,
  postcode: nullableText,
  country: nullableText,
  currency_code: z.literal('GBP'),
  tax_enabled: z.boolean(),
  tax_label: nullableText,
  tax_rate_percent: z.number().min(0).max(100).nullable(),
  tax_registration_number: nullableText
}).superRefine((value, context) => {
  if (!value.tax_enabled && (value.tax_label !== null || value.tax_rate_percent !== null || value.tax_registration_number !== null)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Disabled tax cannot have tax details.' });
  }
  if (value.tax_enabled && (!value.tax_label || value.tax_rate_percent === null)) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Enabled tax requires a label and rate.' });
  }
});

const postcodePrefixSchema = z.string().trim().transform((value) => value.toUpperCase().replace(/\s+/g, '')).refine(
  (value) => /^[A-Z0-9]+$/.test(value),
  'Postcode prefixes may contain letters and numbers only.'
);

export const deliveryZoneInputSchema = z.object({
  name: z.string().trim().min(1, 'Zone name is required.'),
  is_active: z.boolean(),
  postcode_prefixes: z.array(postcodePrefixSchema).min(1, 'Add at least one postcode prefix.').superRefine((prefixes, context) => {
    if (new Set(prefixes).size !== prefixes.length) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: 'Postcode prefixes must be unique within a zone.' });
    }
  }),
  delivery_fee: requiredNonnegativeNumber('Delivery fee'),
  minimum_order: z.number().nonnegative().nullable(),
  match_priority: requiredNonnegativeInteger('Match priority'),
  display_order: requiredNonnegativeInteger('Display order')
});

export type BusinessSettingsInput = z.infer<typeof businessSettingsInputSchema>;
export type DeliveryZoneInput = z.infer<typeof deliveryZoneInputSchema>;

export interface AdminBusinessSettings extends BusinessSettingsInput {
  id: number;
  created_at: string;
  updated_at: string;
}

export interface AdminDeliveryZone extends DeliveryZoneInput {
  id: string;
  created_at: string;
  updated_at: string;
}

export function parsePostcodePrefixes(value: string): string[] {
  return value.split(/[\n,]+/).map((prefix) => prefix.trim()).filter(Boolean);
}
