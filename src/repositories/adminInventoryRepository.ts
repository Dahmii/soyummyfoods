import { getSupabaseClient } from '../lib/supabase';
import type { AdminInventory, AdminInventoryMovement, InventoryAdjustmentInput, InventoryConfigurationInput } from '../types/inventory';

function fail(error: { message: string } | null): void { if (error) throw new Error(error.message); }

export async function listAdminInventory(): Promise<AdminInventory[]> {
  const { data, error } = await getSupabaseClient().from('inventory').select('*, product:products(name, slug, status)').order('updated_at', { ascending: false });
  fail(error); return (data ?? []) as AdminInventory[];
}

export interface InventoryProductOption {
  id: string;
  name: string;
  slug: string;
  status: 'draft' | 'active' | 'archived';
}

export async function listInventoryProducts(): Promise<InventoryProductOption[]> {
  const { data, error } = await getSupabaseClient().from('products').select('id, name, slug, status').order('display_order');
  fail(error); return (data ?? []) as InventoryProductOption[];
}

export async function getAdminInventoryByProduct(productId: string): Promise<AdminInventory | null> {
  const { data, error } = await getSupabaseClient().from('inventory').select('*, product:products(name, slug, status)').eq('product_id', productId).maybeSingle();
  fail(error); return data as AdminInventory | null;
}

export async function listInventoryMovements(inventoryId: string): Promise<AdminInventoryMovement[]> {
  const { data, error } = await getSupabaseClient().from('inventory_movements').select('*').eq('inventory_id', inventoryId).order('created_at', { ascending: false });
  fail(error); return (data ?? []) as AdminInventoryMovement[];
}

export async function configureInventory(productId: string, input: InventoryConfigurationInput): Promise<AdminInventory> {
  const { data, error } = await getSupabaseClient().rpc('configure_product_inventory', {
    p_product_id: productId,
    p_is_tracking_enabled: input.is_tracking_enabled,
    p_low_stock_threshold: input.low_stock_threshold
  });
  fail(error); return data as AdminInventory;
}

export async function adjustInventory(inventoryId: string, input: InventoryAdjustmentInput): Promise<AdminInventory> {
  const { data, error } = await getSupabaseClient().rpc('adjust_inventory', {
    p_inventory_id: inventoryId,
    p_movement_type: input.movement_type,
    p_quantity_delta: input.quantity_delta,
    p_note: input.note
  });
  fail(error); return data as AdminInventory;
}
