import { getSupabaseClient } from '../lib/supabase';
import {
  latePaymentResolutionSchema,
  type LatePaymentReconciliationItem,
  type LatePaymentResolutionInput
} from '../types/adminPaymentReconciliation';

function fail(error: { message: string } | null): void {
  if (error) throw new Error(error.message);
}

export async function listLatePaymentReconciliations(includeResolved = false): Promise<LatePaymentReconciliationItem[]> {
  const { data, error } = await getSupabaseClient().rpc('list_late_payment_reconciliations', {
    p_include_resolved: includeResolved
  });
  fail(error);
  return (data ?? []) as LatePaymentReconciliationItem[];
}

export async function resolveLatePaymentReconciliation(input: LatePaymentResolutionInput): Promise<void> {
  const parsed = latePaymentResolutionSchema.parse(input);
  const { error } = await getSupabaseClient().rpc('resolve_late_payment_reconciliation', {
    p_payment_id: parsed.paymentId,
    p_resolution_code: parsed.resolutionCode,
    p_reference: parsed.reference?.trim() || null,
    p_note: parsed.note?.trim() || null
  });
  fail(error);
}
