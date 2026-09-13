$ErrorActionPreference = 'Stop'

$repository = Get-Content 'src/repositories/adminPaymentReconciliationRepository.ts' -Raw
$page = Get-Content 'src/pages/admin/PaymentReconciliation.tsx' -Raw
$layout = Get-Content 'src/components/admin/AdminLayout.tsx' -Raw
$migration = Get-Content 'supabase/migrations/20260913120000_phase_8a_late_payment_reconciliation.sql' -Raw

foreach ($required in @('list_late_payment_reconciliations', 'resolve_late_payment_reconciliation')) {
  if ($repository -notmatch [regex]::Escape($required)) { throw "Repository does not use $required." }
}
if ($page -notmatch 'does not call Stripe, change the order, or alter inventory' -or $page -notmatch 'Complete any refund manually in Stripe first') {
  throw 'Reconciliation UI does not make the manual, non-mutating workflow explicit.'
}
if ($page -notmatch 'Customer contacted — matter agreed/closed' -or $migration -notmatch 'customer_contacted_closed') {
  throw 'Closed customer-contact reconciliation terminology is missing.'
}
if ($page -match 'Stripe\(' -or $repository -match 'Stripe\(') { throw 'Reconciliation path contains a Stripe API call.' }
if ($layout -notmatch "role === 'owner' \|\| role === 'manager'") { throw 'Reconciliation navigation is not restricted to owner/manager roles.' }
if ($page -notmatch 'if \(!permitted\) return;' -or $page -notmatch 'Manager or owner access is required') {
  throw 'Reconciliation page can load or present data to staff.'
}
if ($migration -notmatch "v_payment\.status <> 'late_success_requires_reconciliation'" -or $migration -notmatch 'not public\.is_manager_or_owner\(\)') {
  throw 'Reconciliation RPC is missing required payment-state or role enforcement.'
}
if ($migration -match 'set status\s*=|update public\.orders|update public\.inventory|inventory_movements') {
  throw 'Reconciliation migration mutates payment status, orders, or inventory.'
}

Write-Output 'Phase 8A static reconciliation verification passed.'
