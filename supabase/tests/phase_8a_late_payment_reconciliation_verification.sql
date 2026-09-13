-- Phase 8A verification. Run after Phases 1-8A in a disposable database only.
-- Replace OWNER_AUTH_USER_UUID / MANAGER_AUTH_USER_UUID / STAFF_AUTH_USER_UUID
-- with real auth.users IDs. Every fixture and mutation is rolled back.

begin;

create temporary table phase_8a_ids (key text primary key, value uuid not null) on commit drop;
grant select, insert, update, delete on table phase_8a_ids to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.resolve_late_payment_reconciliation(uuid,text,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.list_late_payment_reconciliations(boolean)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.resolve_late_payment_reconciliation(uuid,text,text,text)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.list_late_payment_reconciliations(boolean)', 'EXECUTE') then
    raise exception 'A non-admin trusted role can execute a Phase 8A reconciliation RPC';
  end if;
  if not has_function_privilege('authenticated', 'public.resolve_late_payment_reconciliation(uuid,text,text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.list_late_payment_reconciliations(boolean)', 'EXECUTE') then
    raise exception 'Authenticated reconciliation RPC grants are missing';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin perform public.resolve_late_payment_reconciliation('00000000-0000-0000-0000-000000000000', 'refunded'); raise exception 'Anon resolved a payment'; exception when insufficient_privilege then null; end;
  begin perform public.list_late_payment_reconciliations(); raise exception 'Anon read reconciliations'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare
  v_category_id uuid;
  v_product_id uuid;
  v_inventory_id uuid;
begin
  select category_row.id into v_category_id
  from public.categories as category_row
  order by category_row.display_order
  limit 1;
  if v_category_id is null then raise exception 'A seeded category is required'; end if;

  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values (v_category_id, 'phase-8a-reconciliation-test', 'Phase 8A reconciliation test', 'Disposable reconciliation verification product.', 10, 1, 'draft', true, 99960)
  returning id into v_product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order)
  values (v_product_id, '/phase-8a-test.jpg', true, 0);
  update public.products as product_row set status = 'active' where product_row.id = v_product_id;
  select inventory_row.id into v_inventory_id
  from public.configure_product_inventory(v_product_id, true, null) as inventory_row;
  perform public.adjust_inventory(v_inventory_id, 'stock_added', 10, null);
  insert into phase_8a_ids values ('product', v_product_id), ('inventory', v_inventory_id);
end;
$$;

reset role;
set local role service_role;
do $$
declare
  v_product_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'product');
  v_inventory_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'inventory');
  v_late_order_id uuid;
  v_manager_order_id uuid;
  v_wrong_status_order_id uuid;
  v_late_payment_id uuid;
  v_manager_payment_id uuid;
  v_wrong_status_payment_id uuid;
begin
  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, tax_amount, total, reservation_expires_at)
  values ('SYF-20260913-8A000001', gen_random_uuid(), 'phase-8a-late-owner', 'cancelled', 'Phase Eight', 'phase8a@example.test', '1234567', '10 Test Street', 'P8ATEST', 'Phase 8A zone', 10, 0, 0, 10, now() - interval '20 minutes')
  returning id into v_late_order_id;
  insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, quantity, unit_price, line_subtotal)
  values (v_late_order_id, v_product_id, 'phase-8a-reconciliation-test', 'Phase 8A reconciliation test', 1, 10, 10);
  insert into public.order_status_history(order_id, new_status) values (v_late_order_id, 'pending_payment');
  update public.inventory as inventory_row set quantity_reserved = inventory_row.quantity_reserved + 1 where inventory_row.id = v_inventory_id;
  insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
  values (v_inventory_id, v_product_id, 'order_reservation', 0, 10, 10, 1, 0, 1, v_late_order_id, 'order', v_late_order_id);
  update public.inventory as inventory_row set quantity_reserved = inventory_row.quantity_reserved - 1 where inventory_row.id = v_inventory_id;
  insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
  values (v_inventory_id, v_product_id, 'order_release', 0, 10, 10, -1, 1, 0, v_late_order_id, 'order', v_late_order_id);
  insert into public.order_status_history(order_id, previous_status, new_status, reason)
  values (v_late_order_id, 'pending_payment', 'cancelled', 'payment_timeout');
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values (v_late_order_id, 'late_success_requires_reconciliation', 1000, 'GBP', repeat('a', 64), 'pi_phase8a_owner', 'ch_phase8a_owner', '2026-01-01 00:00:00+00'::timestamptz)
  returning id into v_late_payment_id;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, tax_amount, total, reservation_expires_at)
  values ('SYF-20260913-8A000002', gen_random_uuid(), 'phase-8a-late-manager', 'cancelled', 'Phase Eight Manager', 'phase8a-manager@example.test', '1234567', '10 Test Street', 'P8ATEST', 'Phase 8A zone', 10, 0, 0, 10, now() - interval '20 minutes')
  returning id into v_manager_order_id;
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values (v_manager_order_id, 'late_success_requires_reconciliation', 1000, 'GBP', repeat('b', 64), 'pi_phase8a_manager', 'ch_phase8a_manager', '2026-01-01 00:00:01+00'::timestamptz)
  returning id into v_manager_payment_id;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, tax_amount, total, reservation_expires_at)
  values ('SYF-20260913-8A000003', gen_random_uuid(), 'phase-8a-wrong-status', 'confirmed', 'Phase Eight Wrong Status', 'phase8a-wrong@example.test', '1234567', '10 Test Street', 'P8ATEST', 'Phase 8A zone', 10, 0, 0, 10, now() - interval '20 minutes')
  returning id into v_wrong_status_order_id;
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values (v_wrong_status_order_id, 'succeeded', 1000, 'GBP', repeat('c', 64), 'pi_phase8a_wrong', 'ch_phase8a_wrong', '2026-01-01 00:00:02+00'::timestamptz)
  returning id into v_wrong_status_payment_id;

  insert into phase_8a_ids values
    ('late_order', v_late_order_id), ('late_payment', v_late_payment_id),
    ('manager_order', v_manager_order_id), ('manager_payment', v_manager_payment_id),
    ('wrong_status_order', v_wrong_status_order_id), ('wrong_status_payment', v_wrong_status_payment_id);
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare v_late_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'late_payment');
begin
  begin perform public.resolve_late_payment_reconciliation(v_late_payment_id, 'refunded'); raise exception 'Staff resolved a late payment'; exception when insufficient_privilege then null; end;
  begin perform public.list_late_payment_reconciliations(); raise exception 'Staff read late-payment reconciliations'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare
  v_late_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'late_payment');
  v_wrong_status_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'wrong_status_payment');
  v_row record;
begin
  select * into v_row from public.list_late_payment_reconciliations(false) as reconciliation_row
  where reconciliation_row.payment_id = v_late_payment_id;
  if not found or v_row.order_status <> 'cancelled' or v_row.cancellation_reason <> 'payment_timeout' or v_row.reconciled then
    raise exception 'Owner reconciliation queue did not return the required late-payment context';
  end if;

  perform public.resolve_late_payment_reconciliation(v_late_payment_id, 'refunded', 're_phase8a_manual', 'Refund completed manually in Stripe.');
  begin perform public.resolve_late_payment_reconciliation(v_late_payment_id, 'refunded'); raise exception 'Already reconciled payment was accepted'; exception when check_violation then null; end;
  begin perform public.resolve_late_payment_reconciliation(v_wrong_status_payment_id, 'other'); raise exception 'Wrong payment status was accepted'; exception when check_violation then null; end;
end;
$$;

-- Payment, order, inventory, and audit assertions deliberately run as the
-- privileged verification context. Browser-role tests above exercise only RPCs.
reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_late_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'late_payment');
  v_late_order_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'late_order');
  v_inventory_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'inventory');
  v_payment_intent_id text := 'pi_phase8a_owner';
  v_charge_id text := 'ch_phase8a_owner';
  v_succeeded_at timestamptz := '2026-01-01 00:00:00+00'::timestamptz;
begin
  if not exists (
    select 1 from public.payments as payment_row
    where payment_row.id = v_late_payment_id
      and payment_row.status = 'late_success_requires_reconciliation'
      and payment_row.reconciliation_resolved_at is not null
      and payment_row.reconciliation_resolved_by = 'OWNER_AUTH_USER_UUID'::uuid
      and payment_row.reconciliation_resolution_code = 'refunded'
      and payment_row.reconciliation_reference = 're_phase8a_manual'
      and payment_row.reconciliation_note = 'Refund completed manually in Stripe.'
      and payment_row.provider_payment_intent_id = v_payment_intent_id
      and payment_row.provider_charge_id = v_charge_id
      and payment_row.provider_succeeded_at = v_succeeded_at
  ) then raise exception 'Owner reconciliation did not write the expected payment-only fields'; end if;
  if (select order_row.status from public.orders as order_row where order_row.id = v_late_order_id) <> 'cancelled'
     or (select inventory_row.quantity_on_hand from public.inventory as inventory_row where inventory_row.id = v_inventory_id) <> 10
     or (select inventory_row.quantity_reserved from public.inventory as inventory_row where inventory_row.id = v_inventory_id) <> 0
     or (select count(*) from public.inventory_movements as movement_row where movement_row.order_id = v_late_order_id) <> 2 then
    raise exception 'Reconciliation changed order or inventory state';
  end if;
  if not exists (
    select 1 from public.audit_logs as audit_row
    where audit_row.entity_type = 'payment'
      and audit_row.entity_id = v_late_payment_id
      and audit_row.actor_user_id = 'OWNER_AUTH_USER_UUID'::uuid
      and audit_row.old_values = jsonb_build_object('status', 'late_success_requires_reconciliation', 'reconciled', false)
      and audit_row.new_values = jsonb_build_object('status', 'late_success_requires_reconciliation', 'reconciled', true, 'reconciliation_resolution_code', 'refunded', 'reconciliation_reference', 're_phase8a_manual')
  ) then raise exception 'Owner reconciliation audit attribution is missing'; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare
  v_manager_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'manager_payment');
  v_row record;
begin
  select * into v_row from public.list_late_payment_reconciliations(false) as reconciliation_row
  where reconciliation_row.payment_id = v_manager_payment_id;
  if not found or v_row.reconciled then raise exception 'Manager reconciliation queue access failed'; end if;
  perform public.resolve_late_payment_reconciliation(v_manager_payment_id, 'customer_contacted_closed', null, null);
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_manager_payment_id uuid := (select ids.value from phase_8a_ids as ids where ids.key = 'manager_payment');
begin
  if not exists (
    select 1 from public.payments as payment_row
    where payment_row.id = v_manager_payment_id
      and payment_row.status = 'late_success_requires_reconciliation'
      and payment_row.reconciliation_resolved_by = 'MANAGER_AUTH_USER_UUID'::uuid
      and payment_row.reconciliation_resolution_code = 'customer_contacted_closed'
  ) then raise exception 'Manager reconciliation failed'; end if;
end;
$$;

reset role;
rollback;
