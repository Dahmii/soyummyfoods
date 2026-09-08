import { getSupabaseClient } from '../lib/supabase';
import type { AdminBusinessSettings, AdminDeliveryZone, BusinessSettingsInput, DeliveryZoneInput } from '../types/business';

function fail(error: { message: string } | null): void {
  if (error) throw new Error(error.message);
}

export async function getAdminBusinessSettings(): Promise<AdminBusinessSettings> {
  const { data, error } = await getSupabaseClient().from('business_settings').select('*').eq('id', 1).single();
  fail(error);
  return data as AdminBusinessSettings;
}

export async function saveBusinessSettings(input: BusinessSettingsInput): Promise<void> {
  const { error } = await getSupabaseClient().from('business_settings').update(input).eq('id', 1);
  fail(error);
}

export async function listAdminDeliveryZones(): Promise<AdminDeliveryZone[]> {
  const { data, error } = await getSupabaseClient().from('delivery_zones').select('*').order('display_order').order('name');
  fail(error);
  return (data ?? []) as AdminDeliveryZone[];
}

export async function getAdminDeliveryZone(id: string): Promise<AdminDeliveryZone> {
  const { data, error } = await getSupabaseClient().from('delivery_zones').select('*').eq('id', id).single();
  fail(error);
  return data as AdminDeliveryZone;
}

export async function saveDeliveryZone(input: DeliveryZoneInput, id?: string): Promise<string> {
  const client = getSupabaseClient();
  if (id) {
    const { error } = await client.from('delivery_zones').update(input).eq('id', id);
    fail(error);
    return id;
  }
  const { data, error } = await client.from('delivery_zones').insert(input).select('id').single();
  fail(error);
  return data.id as string;
}
