import { z } from 'zod';

export const INVENTORY_MOVEMENT_TYPES = ['stock_added', 'manual_adjustment', 'waste'] as const;
export type InventoryMovementType = (typeof INVENTORY_MOVEMENT_TYPES)[number];

export const inventoryConfigurationSchema = z.object({
  is_tracking_enabled: z.boolean(),
  low_stock_threshold: z.number().int().nonnegative().nullable()
});

export const inventoryAdjustmentSchema = z.object({
  movement_type: z.enum(INVENTORY_MOVEMENT_TYPES),
  quantity_delta: z.number({ invalid_type_error: 'Quantity change is required.' }).int().refine((value) => value !== 0, 'Quantity change cannot be zero.'),
  note: z.string().trim().nullable()
}).superRefine((value, context) => {
  if (['waste', 'manual_adjustment'].includes(value.movement_type) && !value.note) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'A note is required for this movement.' });
  }
});

export type InventoryConfigurationInput = z.infer<typeof inventoryConfigurationSchema>;
export type InventoryAdjustmentInput = z.infer<typeof inventoryAdjustmentSchema>;

export interface AdminInventory {
  id: string;
  product_id: string;
  is_tracking_enabled: boolean;
  quantity_on_hand: number;
  quantity_reserved: number;
  low_stock_threshold: number | null;
  created_at: string;
  updated_at: string;
  product: { name: string; slug: string; status: 'draft' | 'active' | 'archived'; } | null;
}

export interface AdminInventoryMovement {
  id: string;
  inventory_id: string;
  product_id: string;
  movement_type: InventoryMovementType | 'order_deduction' | 'order_restock';
  quantity_delta: number;
  quantity_before: number;
  quantity_after: number;
  note: string | null;
  actor_user_id: string | null;
  created_at: string;
}
