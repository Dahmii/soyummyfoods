-- Phase 5 verification. Run after Phases 1-5 in a disposable database only.
-- Replace UUID placeholders with real auth.users IDs. This suite rolls back.
-- The create_guest_order and expire_pending_order RPCs are intentionally trusted
-- server-only operations; exercise their successful paths through the guest-checkout
-- Edge Function (or a service_role test connection), never by granting browser roles.

begin;

-- Test-only fixture setup. This additional BEFORE INSERT trigger exists only for
-- this transaction and only for the fixed expiry-test idempotency key. It creates
-- an already-expired initial snapshot without mutating any order afterward or
-- weakening the deployed immutable-snapshot trigger.
create function public.phase_5_test_set_expired_reservation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.idempotency_key = '50000000-0000-4000-8000-000000000001'::uuid then
    new.reservation_expires_at = now() - interval '1 second';
  end if;
  return new;
end;
$$;

create trigger phase_5_test_set_expired_reservation_before_insert
before insert on public.orders
for each row execute function public.phase_5_test_set_expired_reservation();

-- Schema, grant, and browser-boundary assertions.
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'inventory' and column_name = 'quantity_reserved') then raise exception 'quantity_reserved missing'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'inventory_movements' and column_name in ('reserved_delta', 'reserved_before', 'reserved_after', 'order_id')) <> 4 then raise exception 'Phase 5 movement columns missing'; end if;
  if not exists (select 1 from pg_constraint where conname = 'inventory_movements_balance_semantics') then raise exception 'Order movement sign constraint missing'; end if;
  if has_function_privilege('anon', 'public.create_guest_order(jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.create_guest_order(jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.expire_pending_order(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.expire_pending_order(uuid)', 'EXECUTE') then
    raise exception 'A browser role can execute a trusted Phase 5 RPC';
  end if;
  if not has_function_privilege('service_role', 'public.create_guest_order(jsonb)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.expire_pending_order(uuid)', 'EXECUTE') then
    raise exception 'Trusted Phase 5 RPC grants are missing';
  end if;
end;
$$;

set local role anon;
do $$ begin
  begin perform 1 from public.orders; raise exception 'Anon read orders'; exception when insufficient_privilege then null; end;
  begin insert into public.orders (order_number, idempotency_key, request_fingerprint, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at) values ('SYF-20260908-AAAAAAAA', gen_random_uuid(), 'x', 'Test User', 'test@example.test', '1234567', 'Address', 'AA11AA', 'Test', 1, 1, 2, now()); raise exception 'Anon inserted order'; exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Trusted-operation test matrix (invoke these through the Edge Function with a
-- service_role-backed disposable test runner):
-- * reject empty/malformed carts, >20 lines, 0/negative/>99 quantities;
-- * merge duplicate UUID lines, reject a merged quantity >99, and make the
--   request fingerprint from that normalized set;
-- * reject missing/draft/archived/unavailable/POR products; select sale_price
--   before base_price; permit untracked products;
-- * reject unsupported postcodes and below-minimum orders; assert an accepted
--   request snapshots resolver zone ID/name/postcode/fee, never £3.50/free-over-£40;
-- * assert tax-disabled => zero tax and tax-enabled/unconfigured => safe failure;
-- * assert discount is always zero and total = subtotal + delivery_fee + tax_amount;
-- * for tracked stock, assert one reservation movement per item with physical
--   delta/before/after unchanged, reserved delta +quantity, typed order FK and
--   reference_type/reference_id = order; insufficient multi-item stock rolls back all;
-- * direct Phase 4 stock_added/manual_adjustment/waste movements retain reserved
--   before/after and cannot lower quantity_on_hand beneath quantity_reserved;
-- * identical idempotency retries return one original order and no extra movements;
--   the same key with changed normalized payload fails;
-- * initial order/history are pending_payment/null-previous-status with a 15-minute
--   reservation expiry, and order items/history/financial snapshots reject mutation;
-- * after expiry, expire_pending_order releases each tracked reservation once,
--   writes order_release rows and cancelled/payment_timeout history; repeated expiry
--   calls are no-ops with no duplicate releases.

-- Two-session disposable-database tests:
-- 1. Final stock: submit two different requests for the last tracked portions.
--    Product locks then inventory locks serialize the requests; exactly one reserves.
-- 2. Lifecycle: a product status/availability update and checkout must serialize on
--    the product FOR SHARE lock. Checkout cannot commit using stale active/available data.
-- 3. Idempotency: two same-key submissions block on the advisory transaction lock;
--    after the first commits, the second returns its original result without a new order.
-- 4. Expiry: two workers target one eligible order; the first locks order -> products
--    -> inventory and releases it, and the second observes cancelled/no-op.
-- 5. Future Phase 7 payment-success vs expiry must lock the same order first; whichever
--    transition commits first wins and the other must re-check status before mutation.

-- Executable trusted-operation coverage. The runner must be able to SET ROLE to
-- service_role (as the Supabase SQL editor/disposable database owner can).
create temporary table phase_5_ids (
  key text primary key,
  value uuid not null
) on commit drop;

grant select, insert, update, delete
on table phase_5_ids
to authenticated;

grant select, insert, update, delete
on table phase_5_ids
to service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12727211-8255-41d8-af95-cf41e784d72b', true);
do $$
declare category_id uuid; product_id uuid; inventory_id uuid; zone_id uuid;
begin
  select id into category_id from public.categories order by display_order limit 1;
  if category_id is null then raise exception 'Seeded category required'; end if;
  insert into public.products(category_id, slug, name, description, base_price, sale_price, prep_time_minutes, status, is_available, display_order)
  values(category_id, 'phase-5-checkout-test', 'Phase 5 checkout test', 'Disposable checkout verification product.', 10, 8, 1, 'draft', true, 99990) returning id into product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order) values(product_id, '/phase-5-test.jpg', true, 0);
  update public.products set status = 'active' where id = product_id;
  select id into inventory_id from public.configure_product_inventory(product_id, true, null);
  perform public.adjust_inventory(inventory_id, 'stock_added', 10, null);
  insert into public.delivery_zones(name, is_active, postcode_prefixes, delivery_fee, minimum_order, match_priority, display_order)
  values('Phase 5 test zone', true, array['P5TEST'], 2.25, 10, 0, 99990) returning id into zone_id;
  update public.business_settings set tax_enabled = false, tax_label = null, tax_rate_percent = null, tax_registration_number = null where id = 1;
  insert into phase_5_ids values ('product', product_id), ('inventory', inventory_id), ('zone', zone_id);
end;
$$;
reset role;

set local role service_role;
do $$
declare created record; test_product_id uuid := (select value from phase_5_ids where key = 'product'); test_inventory_id uuid := (select value from phase_5_ids where key = 'inventory'); test_order_id uuid;
declare payload jsonb;
begin
  payload := jsonb_build_object('idempotency_key', '50000000-0000-4000-8000-000000000001', 'lines', jsonb_build_array(jsonb_build_object('product_id', test_product_id, 'quantity', 1), jsonb_build_object('product_id', test_product_id, 'quantity', 1)), 'customer_name', 'Phase Five', 'customer_email', 'phase5@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P5 TEST', 'customer_note', null);
  select * into created from public.create_guest_order(payload);
  test_order_id := created.order_id;
  insert into phase_5_ids values ('order', test_order_id);
  if created.subtotal <> 16 or created.delivery_fee <> 2.25 or created.tax_amount <> 0 or created.total <> 18.25 or created.status <> 'pending_payment' then raise exception 'Authoritative sale/base, tax-disabled, or total calculation failed'; end if;
  if created.reservation_expires_at >= now() then raise exception 'Expiry fixture was not created expired'; end if;
  if (select i.quantity_reserved from public.inventory i where i.id = test_inventory_id) <> 2 then raise exception 'Duplicate-line normalization/reservation failed'; end if;
  if not exists (select 1 from public.inventory_movements im where im.order_id = test_order_id and im.movement_type = 'order_reservation' and im.quantity_delta = 0 and im.reserved_delta = 2 and im.reserved_before = 0 and im.reserved_after = 2) then raise exception 'Reservation movement snapshot failed'; end if;
  if not exists (select 1 from public.order_status_history h where h.order_id = test_order_id and h.previous_status is null and h.new_status = 'pending_payment' and h.actor_user_id is null) then raise exception 'Initial status history failed'; end if;
  perform 1 from public.create_guest_order(payload);
  if (select count(*) from public.inventory_movements im where im.order_id = test_order_id and im.movement_type = 'order_reservation') <> 1 then raise exception 'Pending idempotent retry duplicated reservation'; end if;
  begin perform public.create_guest_order(payload || jsonb_build_object('customer_note', 'different')); raise exception 'Different-payload idempotency reuse accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.create_guest_order(jsonb_build_object('idempotency_key', '50000000-0000-4000-8000-000000000003', 'lines', jsonb_build_array(jsonb_build_object('product_id', test_product_id, 'quantity', 1)), 'customer_name', 'Phase Five', 'customer_email', 'phase5@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P5 TEST', 'customer_note', null)); raise exception 'Minimum order accepted'; exception when check_violation then null; end;
  begin perform public.create_guest_order(jsonb_build_object('idempotency_key', '50000000-0000-4000-8000-000000000002', 'lines', jsonb_build_array(jsonb_build_object('product_id', test_product_id, 'quantity', 1)), 'customer_name', 'Phase Five', 'customer_email', 'phase5@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'NO MATCH', 'customer_note', null)); raise exception 'Unsupported postcode accepted'; exception when check_violation then null; end;
end;
$$;

-- Tax is intentionally not calculated in Phase 5. Enabling it must fail safely.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '12727211-8255-41d8-af95-cf41e784d72b', true);
update public.business_settings set tax_enabled = true, tax_label = 'Test tax', tax_rate_percent = 20 where id = 1;
reset role;
set local role service_role;
do $$
declare test_product_id uuid := (select value from phase_5_ids where key = 'product');
begin
  begin perform public.create_guest_order(jsonb_build_object('idempotency_key', '50000000-0000-4000-8000-000000000004', 'lines', jsonb_build_array(jsonb_build_object('product_id', test_product_id, 'quantity', 2)), 'customer_name', 'Phase Five', 'customer_email', 'phase5@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P5 TEST', 'customer_note', null)); raise exception 'Tax-enabled checkout was accepted'; exception when check_violation then null; end;
end;
$$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '12727211-8255-41d8-af95-cf41e784d72b', true);
update public.business_settings set tax_enabled = false, tax_label = null, tax_rate_percent = null, tax_registration_number = null where id = 1;

-- The owner cannot disable tracking while the reservation exists, but can after expiry.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '12727211-8255-41d8-af95-cf41e784d72b', true);
do $$
declare test_inventory_id uuid := (select value from phase_5_ids where key = 'inventory'); test_product_id uuid := (select value from phase_5_ids where key = 'product');
begin
  begin perform public.configure_product_inventory(test_product_id, false, null); raise exception 'Tracking disable accepted with a reservation'; exception when check_violation then null; end;
  begin perform public.adjust_inventory(test_inventory_id, 'waste', -9, 'Would cross reserved stock'); raise exception 'Physical quantity dropped below reserved quantity'; exception when check_violation then null; end;
end;
$$;

reset role;
set local role service_role;
do $$
declare test_order_id uuid := (select value from phase_5_ids where key = 'order'); test_product_id uuid := (select value from phase_5_ids where key = 'product'); test_inventory_id uuid := (select value from phase_5_ids where key = 'inventory');
begin
  begin
    insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
    values(test_inventory_id, test_product_id, 'order_reservation', 1, 10, 11, 1, 0, 1, test_order_id, 'order', test_order_id);
    raise exception 'Order reservation sign constraint accepted physical stock change';
  exception when check_violation then null; end;
  begin
    insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after)
    values(test_inventory_id, test_product_id, 'stock_added', 1, 10, 11, 1, 0, 1);
    raise exception 'Ordinary stock movement accepted reservation delta';
  exception when check_violation then null; end;
  perform public.expire_pending_order(test_order_id);
  if (select o.status from public.orders o where o.id = test_order_id) <> 'cancelled' or (select i.quantity_reserved from public.inventory i where i.id = test_inventory_id) <> 0 then raise exception 'Expiry did not cancel and release reservation'; end if;
  if not exists (select 1 from public.inventory_movements im where im.order_id = test_order_id and im.movement_type = 'order_release' and im.quantity_delta = 0 and im.reserved_delta = -2) then raise exception 'Release movement is incorrect'; end if;
  perform public.expire_pending_order(test_order_id);
  if (select count(*) from public.inventory_movements im where im.order_id = test_order_id and im.movement_type = 'order_release') <> 1 then raise exception 'Repeated expiry duplicated release'; end if;
  begin perform public.create_guest_order(jsonb_build_object('idempotency_key', '50000000-0000-4000-8000-000000000001', 'lines', jsonb_build_array(jsonb_build_object('product_id', test_product_id, 'quantity', 2)), 'customer_name', 'Phase Five', 'customer_email', 'phase5@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P5 TEST', 'customer_note', null)); raise exception 'Expired idempotency key was accepted'; exception when check_violation then null; end;
  begin update public.order_items oi set quantity = 3 where oi.order_id = test_order_id; raise exception 'Order items were mutable'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '12727211-8255-41d8-af95-cf41e784d72b', true);
do $$
declare test_product_id uuid := (select value from phase_5_ids where key = 'product');
begin
  perform public.configure_product_inventory(test_product_id, false, null);
  if exists (select 1 from public.inventory i where i.product_id = test_product_id and i.is_tracking_enabled) then raise exception 'Tracking did not disable after reservations cleared'; end if;
end;
$$;
reset role;

rollback;
