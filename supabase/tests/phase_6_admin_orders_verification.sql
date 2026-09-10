-- Phase 6 verification. Run after Phases 1-6 in a disposable database only.
-- Replace the UUID placeholders with real owner, manager, and staff auth.users IDs.
-- Every fixture and mutation below is rolled back.

begin;

create temporary table phase_6_ids (key text primary key, value uuid not null) on commit drop;
grant select, insert, update, delete on table phase_6_ids to authenticated, service_role;

-- Browser boundary: anon has no order access or transition-RPC execution.
set local role anon;
do $$
begin
  begin perform 1 from public.orders; raise exception 'Anon read orders'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.order_items; raise exception 'Anon read order items'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.order_status_history; raise exception 'Anon read order history'; exception when insufficient_privilege then null; end;
  begin perform public.transition_admin_order_status('00000000-0000-0000-0000-000000000000', 'pending_payment', 'cancelled', 'x'); raise exception 'Anon executed transition RPC'; exception when insufficient_privilege then null; end;
  begin perform public.get_admin_order_status_history('00000000-0000-0000-0000-000000000000'); raise exception 'Anon executed status-history helper'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare
  category_id uuid;
  product_id uuid;
  inventory_id uuid;
begin
  if not public.is_owner() then raise exception 'Owner role helper failed'; end if;
  select id into category_id from public.categories order by display_order limit 1;
  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values(category_id, 'phase-6-order-test', 'Phase 6 order test', 'Disposable Phase 6 order test product.', 10, 1, 'draft', true, 99991)
  returning id into product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order) values(product_id, '/phase-6-test.jpg', true, 0);
  update public.products set status = 'active' where id = product_id;
  select id into inventory_id from public.configure_product_inventory(product_id, true, null);
  perform public.adjust_inventory(inventory_id, 'stock_added', 5, null);
  insert into phase_6_ids values ('inventory', inventory_id), ('product', product_id);
end;
$$;

reset role;
set local role service_role;
do $$
declare
  product_id uuid := (select value from phase_6_ids where key = 'product');
  inventory_id uuid := (select value from phase_6_ids where key = 'inventory');
  pending_order_id uuid;
  owner_pending_order_id uuid;
  staff_pending_order_id uuid;
  confirmed_order_id uuid;
begin
  update public.profiles
  set display_name = 'Phase 6 Manager'
  where id = 'MANAGER_AUTH_USER_UUID'::uuid;
  if not found then raise exception 'Manager profile fixture missing'; end if;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at)
  values('SYF-20260909-AAAAAA01', gen_random_uuid(), 'phase-6-pending', 'pending_payment', 'Phase Six', 'phase6@example.test', '1234567', '10 Test Street', 'P6TEST', 'Phase 6 zone', 10, 2, 12, now() + interval '15 minutes')
  returning id into pending_order_id;
  insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, quantity, unit_price, line_subtotal) values(pending_order_id, product_id, 'phase-6-order-test', 'Phase 6 order test', 2, 10, 20);
  update public.inventory set quantity_reserved = 2 where id = inventory_id;
  insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
  values(inventory_id, product_id, 'order_reservation', 0, 5, 5, 2, 0, 2, pending_order_id, 'order', pending_order_id);

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at)
  values('SYF-20260909-AAAAAA03', gen_random_uuid(), 'phase-6-owner-pending', 'pending_payment', 'Phase Six Owner', 'phase6-owner@example.test', '1234567', '10 Test Street', 'P6TEST', 'Phase 6 zone', 10, 2, 12, now() + interval '15 minutes')
  returning id into owner_pending_order_id;
  insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, quantity, unit_price, line_subtotal) values(owner_pending_order_id, product_id, 'phase-6-order-test', 'Phase 6 order test', 1, 10, 10);
  update public.inventory set quantity_reserved = 3 where id = inventory_id;
  insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
  values(inventory_id, product_id, 'order_reservation', 0, 5, 5, 1, 2, 3, owner_pending_order_id, 'order', owner_pending_order_id);

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at)
  values('SYF-20260909-AAAAAA04', gen_random_uuid(), 'phase-6-staff-pending', 'pending_payment', 'Phase Six Staff', 'phase6-staff@example.test', '1234567', '10 Test Street', 'P6TEST', 'Phase 6 zone', 10, 2, 12, now() + interval '15 minutes')
  returning id into staff_pending_order_id;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at)
  values('SYF-20260909-AAAAAA02', gen_random_uuid(), 'phase-6-confirmed', 'confirmed', 'Phase Six', 'phase6@example.test', '1234567', '10 Test Street', 'P6TEST', 'Phase 6 zone', 10, 2, 12, now() + interval '15 minutes')
  returning id into confirmed_order_id;
  insert into public.order_status_history(order_id, new_status) values(confirmed_order_id, 'confirmed');
  insert into phase_6_ids values ('pending_order', pending_order_id), ('owner_pending_order', owner_pending_order_id), ('staff_pending_order', staff_pending_order_id), ('confirmed_order', confirmed_order_id);
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
begin
  if not exists (select 1 from public.orders) or not exists (select 1 from public.order_items) or not exists (select 1 from public.order_status_history) then
    raise exception 'Owner read policies failed';
  end if;
end;
$$;

-- An authenticated user without an application role remains invisible to order RLS
-- and cannot use either security-definer helper.
select set_config('request.jwt.claim.sub', 'NON_STAFF_AUTH_USER_UUID', true);
do $$
declare pending_order_id uuid := (select value from phase_6_ids where key = 'pending_order');
begin
  if exists (select 1 from public.orders) then raise exception 'Authenticated non-staff read orders'; end if;
  if exists (select 1 from public.order_items) then raise exception 'Authenticated non-staff read order items'; end if;
  if exists (select 1 from public.order_status_history) then raise exception 'Authenticated non-staff read order history'; end if;
  begin perform public.transition_admin_order_status(pending_order_id, 'pending_payment', 'cancelled', 'No role'); raise exception 'Authenticated non-staff executed transition RPC'; exception when insufficient_privilege then null; end;
  begin perform public.get_admin_order_status_history(pending_order_id); raise exception 'Authenticated non-staff executed status-history helper'; exception when insufficient_privilege then null; end;
end;
$$;

-- Manager can cancel a pending order once and receives authoritative attribution.
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare pending_order_id uuid := (select value from phase_6_ids where key = 'pending_order'); inventory_id uuid := (select value from phase_6_ids where key = 'inventory');
begin
  if not public.is_manager_or_owner() or public.is_owner() then raise exception 'Manager role helper failed'; end if;
  if not exists (select 1 from public.orders) or not exists (select 1 from public.order_items) or not exists (select 1 from public.order_status_history) then raise exception 'Manager read policies failed'; end if;
  begin perform public.transition_admin_order_status(pending_order_id, 'pending_payment', 'confirmed', null); raise exception 'Manual payment confirmation accepted'; exception when check_violation then null; end;
  begin perform public.transition_admin_order_status(pending_order_id, 'pending_payment', 'cancelled', ' '); raise exception 'Blank cancellation reason accepted'; exception when invalid_parameter_value then null; end;
  perform public.transition_admin_order_status(pending_order_id, 'pending_payment', 'cancelled', 'Customer cancelled before payment');
  if (select status from public.orders where id = pending_order_id) <> 'cancelled' then raise exception 'Manager cancellation failed'; end if;
  if (select quantity_reserved from public.inventory where id = inventory_id) <> 1 or (select quantity_on_hand from public.inventory where id = inventory_id) <> 5 then raise exception 'Cancellation reservation release changed the wrong inventory balance'; end if;
  if (select count(*) from public.inventory_movements where order_id = pending_order_id and movement_type = 'order_release') <> 1 then raise exception 'Cancellation did not write exactly one release'; end if;
  if not exists (select 1 from public.order_status_history where order_id = pending_order_id and previous_status = 'pending_payment' and new_status = 'cancelled' and actor_user_id = auth.uid() and reason = 'Customer cancelled before payment') then raise exception 'Cancellation history attribution failed'; end if;
  if exists (select 1 from public.audit_logs) then raise exception 'Manager read owner-only audit logs'; end if;
  begin perform public.transition_admin_order_status(pending_order_id, 'pending_payment', 'cancelled', 'Duplicate'); raise exception 'Stale cancellation accepted'; exception when serialization_failure then null; end;
  if (select count(*) from public.inventory_movements where order_id = pending_order_id and movement_type = 'order_release') <> 1 then raise exception 'Duplicate cancellation released stock twice'; end if;
  begin delete from public.orders where id = pending_order_id; raise exception 'Manager deleted order'; exception when insufficient_privilege then null; end;
  begin insert into public.audit_logs(actor_user_id, action, entity_type, entity_id) values(auth.uid(), 'update', 'order', pending_order_id); raise exception 'Manager inserted audit row'; exception when insufficient_privilege then null; end;
end;
$$;

-- Audit rows are owner-readable only, so verify the manager-attributed row from
-- the trusted verification context rather than expecting manager RLS to expose it.
reset role;
set local role service_role;
do $$
declare pending_order_id uuid := (select value from phase_6_ids where key = 'pending_order');
begin
  if not exists (select 1 from public.audit_logs where entity_type = 'order' and entity_id = pending_order_id and action = 'update' and actor_user_id = 'MANAGER_AUTH_USER_UUID'::uuid and old_values = jsonb_build_object('status', 'pending_payment') and new_values = jsonb_build_object('status', 'cancelled', 'reason', 'Customer cancelled before payment')) then raise exception 'Manager compact cancellation audit missing'; end if;
end;
$$;

reset role;
set local role authenticated;
-- Owner has the same pending-cancellation authority, proven with an independent
-- outstanding reservation rather than the manager fixture above.
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare owner_pending_order_id uuid := (select value from phase_6_ids where key = 'owner_pending_order'); inventory_id uuid := (select value from phase_6_ids where key = 'inventory');
begin
  perform public.transition_admin_order_status(owner_pending_order_id, 'pending_payment', 'cancelled', 'Owner cancelled before payment');
  if (select status from public.orders where id = owner_pending_order_id) <> 'cancelled' then raise exception 'Owner cancellation failed'; end if;
  if (select quantity_reserved from public.inventory where id = inventory_id) <> 0 or (select quantity_on_hand from public.inventory where id = inventory_id) <> 5 then raise exception 'Owner cancellation changed the wrong inventory balance'; end if;
  if (select count(*) from public.inventory_movements where order_id = owner_pending_order_id and movement_type = 'order_release') <> 1 then raise exception 'Owner cancellation did not write exactly one release'; end if;
  if not exists (select 1 from public.order_status_history where order_id = owner_pending_order_id and previous_status = 'pending_payment' and new_status = 'cancelled' and actor_user_id = auth.uid() and reason = 'Owner cancelled before payment') then raise exception 'Owner cancellation history attribution failed'; end if;
  if not exists (select 1 from public.audit_logs where entity_type = 'order' and entity_id = owner_pending_order_id and action = 'update' and actor_user_id = auth.uid() and old_values = jsonb_build_object('status', 'pending_payment') and new_values = jsonb_build_object('status', 'cancelled', 'reason', 'Owner cancelled before payment')) then raise exception 'Owner compact cancellation audit missing'; end if;
  begin perform public.transition_admin_order_status(owner_pending_order_id, 'pending_payment', 'cancelled', 'Duplicate'); raise exception 'Owner stale cancellation accepted'; exception when serialization_failure then null; end;
  if (select count(*) from public.inventory_movements where order_id = owner_pending_order_id and movement_type = 'order_release') <> 1 then raise exception 'Owner duplicate cancellation released stock twice'; end if;
end;
$$;

-- Staff reads operational records and can advance confirmed work, but cannot cancel or write tables directly.
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare confirmed_order_id uuid := (select value from phase_6_ids where key = 'confirmed_order'); pending_order_id uuid := (select value from phase_6_ids where key = 'pending_order'); staff_pending_order_id uuid := (select value from phase_6_ids where key = 'staff_pending_order'); manager_display text := 'Phase 6 Manager';
begin
  if not public.is_staff_or_above() or public.is_manager_or_owner() then raise exception 'Staff role helper failed'; end if;
  if not exists (select 1 from public.orders) or not exists (select 1 from public.order_items) or not exists (select 1 from public.order_status_history) then raise exception 'Staff read policies failed'; end if;
  if not exists (select 1 from public.get_admin_order_status_history(confirmed_order_id) where actor_user_id is null and actor_display_name = 'System') then raise exception 'Status-history helper did not label a system actor'; end if;
  if not exists (select 1 from public.get_admin_order_status_history(pending_order_id) where actor_user_id = 'MANAGER_AUTH_USER_UUID'::uuid and actor_display_name = manager_display) then raise exception 'Status-history helper did not resolve the manager display name'; end if;
  if exists (select 1 from public.get_admin_order_status_history('00000000-0000-0000-0000-000000000000')) then raise exception 'Status-history helper returned data for an unrelated order UUID'; end if;
  begin perform public.transition_admin_order_status(confirmed_order_id, 'confirmed', 'cancelled', 'No'); raise exception 'Confirmed cancellation accepted'; exception when check_violation then null; end;
  begin perform public.transition_admin_order_status(staff_pending_order_id, 'pending_payment', 'cancelled', 'Staff must not cancel'); raise exception 'Staff pending-payment cancellation accepted'; exception when insufficient_privilege then null; end;
  if (select status from public.orders where id = staff_pending_order_id) <> 'pending_payment' then raise exception 'Staff pending-payment cancellation changed the order'; end if;
  perform public.transition_admin_order_status(confirmed_order_id, 'confirmed', 'preparing', null);
  perform public.transition_admin_order_status(confirmed_order_id, 'preparing', 'ready', null);
  perform public.transition_admin_order_status(confirmed_order_id, 'ready', 'completed', null);
  begin perform public.transition_admin_order_status(confirmed_order_id, 'completed', 'ready', null); raise exception 'Backward transition accepted'; exception when check_violation then null; end;
  begin perform public.transition_admin_order_status(confirmed_order_id, 'completed', 'confirmed', null); raise exception 'Skipped transition accepted'; exception when check_violation then null; end;
  begin update public.orders set status = 'confirmed' where id = confirmed_order_id; raise exception 'Staff directly updated order'; exception when insufficient_privilege then null; end;
  begin update public.order_items set quantity = 2 where order_id = confirmed_order_id; raise exception 'Staff mutated item snapshot'; exception when insufficient_privilege then null; end;
  begin delete from public.order_status_history where order_id = confirmed_order_id; raise exception 'Staff deleted status history'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
do $$
begin
  if has_function_privilege('anon', 'public.transition_admin_order_status(uuid,public.order_status,public.order_status,text)', 'EXECUTE') then raise exception 'Anon received transition RPC access'; end if;
  if not has_function_privilege('authenticated', 'public.transition_admin_order_status(uuid,public.order_status,public.order_status,text)', 'EXECUTE') then raise exception 'Authenticated transition RPC grant missing'; end if;
  if exists (select 1 from pg_policies where tablename in ('orders', 'order_items', 'order_status_history') and qual::text like '%user_roles%') then raise exception 'Order policies must use role helpers, not recursive user_roles policies'; end if;
end;
$$;

rollback;
