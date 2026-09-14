-- Phase 7E verification. Run after Phases 1-7E in a disposable database only.
-- Replace OWNER_AUTH_USER_UUID with a real owner auth.users ID. All fixtures roll back.

begin;

create temporary table phase_7e_ids (key text primary key, value uuid not null) on commit drop;
grant select, insert, update, delete on table phase_7e_ids to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.expire_overdue_pending_orders(integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.expire_overdue_pending_orders(integer)', 'EXECUTE') then
    raise exception 'A browser role can execute the expiry batch function';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.expire_overdue_pending_orders(1);
    raise exception 'Anon executed the expiry batch function';
  exception when insufficient_privilege then null;
  end;
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
  select category.id into v_category_id
  from public.categories as category
  order by category.display_order
  limit 1;
  if v_category_id is null then raise exception 'A seeded category is required'; end if;

  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values (v_category_id, 'phase-7e-expiry-test', 'Phase 7E expiry test', 'Disposable pending-payment expiry test product.', 10, 1, 'draft', true, 99970)
  returning id into v_product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order)
  values (v_product_id, '/phase-7e-test.jpg', true, 0);
  update public.products as product
  set status = 'active'
  where product.id = v_product_id;
  select inventory.id into v_inventory_id
  from public.configure_product_inventory(v_product_id, true, null) as inventory;
  perform public.adjust_inventory(v_inventory_id, 'stock_added', 10, null);

  insert into phase_7e_ids values ('product', v_product_id), ('inventory', v_inventory_id);
end;
$$;

reset role;
set local role service_role;
do $$
declare
  v_product_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'product');
  v_inventory_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'inventory');
  v_fixture record;
  v_order_id uuid;
  v_reserved_before integer;
  v_reserved_after integer;
begin
  for v_fixture in
    select *
    from (values
      -- These controlled overdue fixtures sort before every real So Yummy
      -- order, keeping the bounded batches isolated in a shared database.
      ('single_overdue'::text, 'pending_payment'::public.order_status, '2000-01-01 00:00:01+00'::timestamptz, 2),
      ('batch_first'::text, 'pending_payment'::public.order_status, '2000-01-01 00:00:02+00'::timestamptz, 1),
      ('batch_second'::text, 'pending_payment'::public.order_status, '2000-01-01 00:00:03+00'::timestamptz, 1),
      ('future_pending'::text, 'pending_payment'::public.order_status, now() + interval '15 minutes', 1),
      ('confirmed_order'::text, 'confirmed'::public.order_status, now() - interval '5 minutes', 0)
    ) as fixture(fixture_key, order_status, expires_at, reserved_quantity)
  loop
    insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, total, reservation_expires_at)
    values (
      case v_fixture.fixture_key
        when 'single_overdue' then 'SYF-20260911-7E000001'
        when 'batch_first' then 'SYF-20260911-7E000002'
        when 'batch_second' then 'SYF-20260911-7E000003'
        when 'future_pending' then 'SYF-20260911-7E000004'
        else 'SYF-20260911-7E000005'
      end,
      gen_random_uuid(),
      'phase-7e-' || v_fixture.fixture_key,
      v_fixture.order_status,
      'Phase Seven E',
      'phase7e@example.test',
      '1234567',
      '10 Test Street',
      'P7ETEST',
      'Phase 7E zone',
      greatest(v_fixture.reserved_quantity, 1) * 10,
      0,
      greatest(v_fixture.reserved_quantity, 1) * 10,
      v_fixture.expires_at
    ) returning id into v_order_id;

    insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, quantity, unit_price, line_subtotal)
    values (v_order_id, v_product_id, 'phase-7e-expiry-test', 'Phase 7E expiry test', greatest(v_fixture.reserved_quantity, 1), 10, greatest(v_fixture.reserved_quantity, 1) * 10);
    insert into public.order_status_history(order_id, new_status)
    values (v_order_id, v_fixture.order_status);
    insert into phase_7e_ids values (v_fixture.fixture_key, v_order_id);

    if v_fixture.reserved_quantity > 0 then
      select inventory.quantity_reserved into v_reserved_before
      from public.inventory as inventory
      where inventory.id = v_inventory_id;
      update public.inventory as inventory
      set quantity_reserved = inventory.quantity_reserved + v_fixture.reserved_quantity
      where inventory.id = v_inventory_id
      returning inventory.quantity_reserved into v_reserved_after;
      insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
      values (v_inventory_id, v_product_id, 'order_reservation', 0, 10, 10, v_fixture.reserved_quantity, v_reserved_before, v_reserved_after, v_order_id, 'order', v_order_id);
    end if;
  end loop;
end;
$$;

-- The batch function is infrastructure-only: execute it from the trusted
-- database-owner context, not the service_role fixture context.
reset role;
do $$
declare
  v_inventory_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'inventory');
  v_single_order_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'single_overdue');
  v_first_order_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'batch_first');
  v_second_order_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'batch_second');
  v_future_order_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'future_pending');
  v_confirmed_order_id uuid := (select ids.value from phase_7e_ids as ids where ids.key = 'confirmed_order');
  v_count integer;
begin
  v_count := public.expire_overdue_pending_orders(1);
  if v_count <> 1 then raise exception 'First bounded expiry batch did not process one candidate'; end if;
  if (select order_row.status from public.orders as order_row where order_row.id = v_single_order_id) <> 'cancelled'
     or (select order_row.status from public.orders as order_row where order_row.id = v_first_order_id) <> 'pending_payment'
     or (select order_row.status from public.orders as order_row where order_row.id = v_second_order_id) <> 'pending_payment' then
    raise exception 'First bounded expiry batch did not select only the oldest fixture';
  end if;
  if (select inventory.quantity_on_hand from public.inventory as inventory where inventory.id = v_inventory_id) <> 10
     or (select inventory.quantity_reserved from public.inventory as inventory where inventory.id = v_inventory_id) <> 3 then
    raise exception 'First expiry changed the wrong inventory balance';
  end if;
  if (select count(*) from public.inventory_movements as movement where movement.order_id = v_single_order_id and movement.movement_type = 'order_release' and movement.quantity_delta = 0 and movement.reserved_delta = -2) <> 1 then
    raise exception 'First expiry did not create exactly one correct release movement';
  end if;
  if (select count(*) from public.order_status_history as history where history.order_id = v_single_order_id and history.previous_status = 'pending_payment' and history.new_status = 'cancelled' and history.reason = 'payment_timeout') <> 1 then
    raise exception 'First expiry did not create exactly one payment-timeout history row';
  end if;

  v_count := public.expire_overdue_pending_orders(1);
  if v_count <> 1
     or (select order_row.status from public.orders as order_row where order_row.id = v_first_order_id) <> 'cancelled'
     or (select order_row.status from public.orders as order_row where order_row.id = v_second_order_id) <> 'pending_payment' then
    raise exception 'Batch size/order selection was not respected';
  end if;

  v_count := public.expire_overdue_pending_orders(1);
  if v_count <> 1 then raise exception 'Third bounded expiry batch did not process one candidate'; end if;
  if (select order_row.status from public.orders as order_row where order_row.id = v_second_order_id) <> 'cancelled' then raise exception 'Remaining overdue order was not cancelled'; end if;
  if (select order_row.status from public.orders as order_row where order_row.id = v_future_order_id) <> 'pending_payment' then raise exception 'Future pending order was changed'; end if;
  if (select order_row.status from public.orders as order_row where order_row.id = v_confirmed_order_id) <> 'confirmed' then raise exception 'Confirmed order was changed'; end if;
  if (select inventory.quantity_on_hand from public.inventory as inventory where inventory.id = v_inventory_id) <> 10
     or (select inventory.quantity_reserved from public.inventory as inventory where inventory.id = v_inventory_id) <> 1 then
    raise exception 'Batch expiry changed the wrong final inventory balance';
  end if;

  perform public.expire_pending_order(v_single_order_id);
  if (select count(*) from public.inventory_movements as movement where movement.order_id = v_single_order_id and movement.movement_type = 'order_release') <> 1 then
    raise exception 'Repeated expiry duplicated a release movement';
  end if;
  if (select count(*) from public.order_status_history as history where history.order_id = v_single_order_id and history.previous_status = 'pending_payment' and history.new_status = 'cancelled' and history.reason = 'payment_timeout') <> 1 then
    raise exception 'Repeated expiry duplicated a payment-timeout history row';
  end if;

  begin
    perform public.expire_overdue_pending_orders(0);
    raise exception 'Zero batch size was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.expire_overdue_pending_orders(101);
    raise exception 'Oversized batch was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.expire_overdue_pending_orders(null);
    raise exception 'Null batch size was accepted';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
begin
  begin
    perform public.expire_overdue_pending_orders(1);
    raise exception 'Authenticated user executed the expiry batch function';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
