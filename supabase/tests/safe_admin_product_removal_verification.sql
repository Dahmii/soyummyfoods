-- Safe product-removal verification. Run after all current migrations in a
-- disposable database only. Every fixture is rolled back.
--
-- Required operator input: replace OWNER_AUTH_USER_UUID,
-- MANAGER_AUTH_USER_UUID, and STAFF_AUTH_USER_UUID below with three distinct
-- real auth.users IDs. The preflight validates that each has a profile and its
-- required application role before role-specific assertions run.

begin;

set local role service_role;
do $$
declare
  v_owner uuid := 'OWNER_AUTH_USER_UUID'::uuid;
  v_manager uuid := 'MANAGER_AUTH_USER_UUID'::uuid;
  v_staff uuid := 'STAFF_AUTH_USER_UUID'::uuid;
begin
  if v_owner = v_manager or v_owner = v_staff or v_manager = v_staff then
    raise exception 'Owner, manager, and staff fixture users must be distinct';
  end if;

  if not exists (
    select 1 from auth.users as auth_user
    where auth_user.id in (v_owner, v_manager, v_staff)
  ) or (
    select count(*) from public.profiles as profile_row
    where profile_row.id in (v_owner, v_manager, v_staff)
  ) <> 3 then
    raise exception 'Configured fixture Auth users or profiles are missing';
  end if;

  if not exists (
    select 1 from public.user_roles as role_row
    where role_row.user_id = v_owner and role_row.role = 'owner'::public.app_role
  ) or not exists (
    select 1 from public.user_roles as role_row
    where role_row.user_id = v_manager and role_row.role = 'manager'::public.app_role
  ) or not exists (
    select 1 from public.user_roles as role_row
    where role_row.user_id = v_staff and role_row.role = 'staff'::public.app_role
  ) then
    raise exception 'Configured fixture users do not have the required owner, manager, and staff roles';
  end if;
end;
$$;

reset role;

do $$
declare
  v_plan_definition text;
  v_remove_definition text;
begin
  if has_function_privilege('anon', 'public.get_admin_product_removal_plan(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.get_admin_product_removal_plan(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_admin_product_removal_plan(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.remove_admin_product(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.remove_admin_product(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.remove_admin_product(uuid)', 'EXECUTE') then
    raise exception 'Safe product-removal RPC grants are incorrect';
  end if;

  select pg_get_functiondef('public.get_admin_product_removal_plan(uuid)'::regprocedure)
    into v_plan_definition;
  select pg_get_functiondef('public.remove_admin_product(uuid)'::regprocedure)
    into v_remove_definition;
  if position('security definer' in lower(v_plan_definition)) = 0
     or not exists (
       select 1
       from pg_proc as function_row
       where function_row.oid = 'public.get_admin_product_removal_plan(uuid)'::regprocedure
         and function_row.proconfig @> array['search_path=pg_catalog, public']
     )
     or position('public.order_items' in lower(v_plan_definition)) = 0
     or position('public.inventory_movements' in lower(v_plan_definition)) = 0
     or position('quantity_on_hand <> 0' in lower(v_plan_definition)) = 0
     or position('security definer' in lower(v_remove_definition)) = 0
     or not exists (
       select 1
       from pg_proc as function_row
       where function_row.oid = 'public.remove_admin_product(uuid)'::regprocedure
         and function_row.proconfig @> array['search_path=pg_catalog, public']
     )
     or position('for update' in lower(v_remove_definition)) = 0
     or position('update public.products' in lower(v_remove_definition)) = 0
     or position('quantity_on_hand <> 0' in lower(v_remove_definition)) = 0
     or position('delete from public.inventory' in lower(v_remove_definition)) = 0
     or position('delete from public.products' in lower(v_remove_definition)) = 0 then
    raise exception 'Safe product-removal implementation is incomplete';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and cmd = 'DELETE'
  ) then
    raise exception 'Products must not gain a direct DELETE policy';
  end if;
end;
$$;

set local role service_role;
do $$
declare
  v_category_id uuid := '00000000-0000-4000-8000-00000000011a'::uuid;
  v_removable_product_id uuid := '00000000-0000-4000-8000-00000000011b'::uuid;
  v_ordered_product_id uuid := '00000000-0000-4000-8000-00000000011c'::uuid;
  v_movement_product_id uuid := '00000000-0000-4000-8000-00000000011d'::uuid;
  v_inventory_id uuid := '00000000-0000-4000-8000-00000000011e'::uuid;
  v_order_id uuid := '00000000-0000-4000-8000-00000000011f'::uuid;
  v_payment_id uuid := '00000000-0000-4000-8000-000000000120'::uuid;
  v_document_id uuid := '00000000-0000-4000-8000-000000000121'::uuid;
  v_stocked_product_id uuid := '00000000-0000-4000-8000-000000000122'::uuid;
  v_stocked_inventory_id uuid := '00000000-0000-4000-8000-000000000123'::uuid;
  v_product_audit_id uuid := '00000000-0000-4000-8000-000000000124'::uuid;
begin
  insert into public.categories (id, name, slug, display_order)
  values (v_category_id, 'Removal verification category', 'safe-product-removal-verification', 99999);

  insert into public.products (
    id, category_id, slug, name, description, base_price,
    prep_time_minutes, status, display_order
  ) values
    (v_removable_product_id, v_category_id, 'safe-product-removal-delete', 'Removable product', 'Disposable product.', 1, 1, 'draft', 99999),
    (v_ordered_product_id, v_category_id, 'safe-product-removal-order', 'Ordered product', 'Disposable product.', 1, 1, 'draft', 99998),
    (v_movement_product_id, v_category_id, 'safe-product-removal-movement', 'Movement product', 'Disposable product.', 1, 1, 'draft', 99997),
    (v_stocked_product_id, v_category_id, 'safe-product-removal-stocked', 'Stocked product', 'Disposable product.', 1, 1, 'draft', 99996);

  insert into public.inventory (id, product_id, is_tracking_enabled)
  values (v_inventory_id, v_removable_product_id, false);

  insert into public.orders (
    id, order_number, idempotency_key, request_fingerprint, status,
    customer_name, customer_email, customer_phone, delivery_address,
    postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee,
    discount_amount, tax_amount, total, currency_code, reservation_expires_at
  ) values (
    v_order_id, 'SYF-20261020-11A00001', gen_random_uuid(), 'safe-product-removal-order', 'cancelled',
    'Removal Test', 'removal@example.test', '1234567', '1 Test Street',
    'T1ST', 'Removal verification zone', 1, 0, 0, 0, 1, 'GBP', now()
  );
  insert into public.order_items (
    order_id, product_id, product_slug_snapshot, product_name_snapshot,
    quantity, unit_price, line_subtotal
  ) values (
    v_order_id, v_ordered_product_id, 'safe-product-removal-order', 'Ordered product',
    1, 1, 1
  );
  insert into public.payments (
    id, order_id, status, amount_minor, currency_code, payment_capability_hash,
    provider_payment_intent_id, provider_charge_id, provider_succeeded_at
  ) values (
    v_payment_id, v_order_id, 'succeeded', 100, 'GBP', repeat('a', 64),
    'pi_safe_product_removal', 'ch_safe_product_removal', now()
  );
  insert into public.financial_documents (
    id, document_type, document_number, order_id, payment_id,
    issuer_snapshot, customer_snapshot, financial_snapshot, issuance_origin
  ) values (
    v_document_id, 'receipt', 'RCPT-9999999997', v_order_id, v_payment_id,
    '{}'::jsonb, '{}'::jsonb,
    jsonb_build_object('order_number', 'SYF-20261020-11A00001', 'items', '[]'::jsonb),
    'system'
  );

  -- Do not infer audit preservation from catalog-trigger side effects. This
  -- fixture-owned row is the exact immutable audit evidence asserted later.
  insert into public.audit_logs (
    id, actor_user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    v_product_audit_id, null, 'insert', 'product', v_ordered_product_id,
    null, jsonb_build_object('fixture', 'safe_admin_product_removal')
  );

  insert into public.inventory (product_id, is_tracking_enabled, quantity_on_hand)
  values (v_movement_product_id, true, 1);
  insert into public.inventory_movements (
    inventory_id, product_id, movement_type, quantity_delta, quantity_before,
    quantity_after, reserved_delta, reserved_before, reserved_after
  )
  select inventory_row.id, inventory_row.product_id, 'stock_added', 1, 0, 1, 0, 0, 0
  from public.inventory as inventory_row
  where inventory_row.product_id = v_movement_product_id;

  -- This nonstandard fixture deliberately has a positive reserved balance with
  -- no ledger rows, proving the defensive stock-preservation branch itself.
  insert into public.inventory (
    id, product_id, is_tracking_enabled, quantity_on_hand, quantity_reserved
  ) values (
    v_stocked_inventory_id, v_stocked_product_id, true, 2, 1
  );
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
declare
  v_plan_denied boolean := false;
  v_removal_denied boolean := false;
begin
  begin
    perform public.get_admin_product_removal_plan('00000000-0000-4000-8000-00000000011b');
  exception when insufficient_privilege then
    v_plan_denied := true;
  end;
  if not v_plan_denied then raise exception 'Anon could inspect a product-removal plan'; end if;

  begin
    perform public.remove_admin_product('00000000-0000-4000-8000-00000000011b');
  exception when insufficient_privilege then
    v_removal_denied := true;
  end;
  if not v_removal_denied then raise exception 'Anon could remove a product'; end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
set local role authenticated;
do $$
declare
  v_plan_denied boolean := false;
  v_removal_denied boolean := false;
begin
  begin
    perform public.get_admin_product_removal_plan('00000000-0000-4000-8000-00000000011b');
  exception when insufficient_privilege then
    v_plan_denied := true;
  end;
  if not v_plan_denied then raise exception 'Staff could inspect a product-removal plan'; end if;

  begin
    perform public.remove_admin_product('00000000-0000-4000-8000-00000000011b');
  exception when insufficient_privilege then
    v_removal_denied := true;
  end;
  if not v_removal_denied then raise exception 'Staff could remove a product'; end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
set local role authenticated;
do $$
declare
  v_action text;
begin
  select removal_action into v_action
  from public.get_admin_product_removal_plan('00000000-0000-4000-8000-00000000011b');
  if v_action <> 'delete' then raise exception 'A product without operational history was not planned for deletion'; end if;

  select removal_action into v_action
  from public.remove_admin_product('00000000-0000-4000-8000-00000000011b');
  if v_action <> 'deleted'
     or exists (select 1 from public.products where id = '00000000-0000-4000-8000-00000000011b')
     or exists (select 1 from public.inventory where id = '00000000-0000-4000-8000-00000000011e') then
    raise exception 'Manager deletion did not atomically remove a history-free product and its inventory configuration';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
set local role authenticated;
do $$
declare
  v_action text;
begin
  select removal_action into v_action
  from public.get_admin_product_removal_plan('00000000-0000-4000-8000-00000000011c');
  if v_action <> 'archive' then raise exception 'An order-referenced product was planned for deletion'; end if;
  select removal_action into v_action
  from public.remove_admin_product('00000000-0000-4000-8000-00000000011c');
  if v_action <> 'archived'
     or not exists (
       select 1 from public.products
       where id = '00000000-0000-4000-8000-00000000011c'
         and status = 'archived'::public.product_status
         and not is_available
     )
     or not exists (select 1 from public.orders where id = '00000000-0000-4000-8000-00000000011f')
     or not exists (select 1 from public.order_items where product_id = '00000000-0000-4000-8000-00000000011c') then
    raise exception 'Owner archival did not preserve order history';
  end if;

  select removal_action into v_action
  from public.get_admin_product_removal_plan('00000000-0000-4000-8000-00000000011d');
  if v_action <> 'archive' then raise exception 'An inventory-history product was planned for deletion'; end if;
  select removal_action into v_action
  from public.remove_admin_product('00000000-0000-4000-8000-00000000011d');
  if v_action <> 'archived'
     or not exists (select 1 from public.inventory_movements where product_id = '00000000-0000-4000-8000-00000000011d') then
    raise exception 'Owner archival did not preserve inventory history';
  end if;

  select removal_action into v_action
  from public.get_admin_product_removal_plan('00000000-0000-4000-8000-000000000122');
  if v_action <> 'archive' then raise exception 'A product with nonzero/reserved stock was planned for deletion'; end if;
  select removal_action into v_action
  from public.remove_admin_product('00000000-0000-4000-8000-000000000122');
  if v_action <> 'archived'
     or not exists (
       select 1 from public.inventory
       where id = '00000000-0000-4000-8000-000000000123'
         and quantity_on_hand = 2
         and quantity_reserved = 1
     ) then
    raise exception 'Owner archival did not preserve nonzero/reserved inventory';
  end if;
end;
$$;

reset role;
set local role service_role;
do $$
begin
  if not exists (select 1 from public.orders where id = '00000000-0000-4000-8000-00000000011f')
     or not exists (select 1 from public.order_items where product_id = '00000000-0000-4000-8000-00000000011c')
     or not exists (select 1 from public.payments where id = '00000000-0000-4000-8000-000000000120')
     or not exists (select 1 from public.financial_documents where id = '00000000-0000-4000-8000-000000000121')
     or not exists (select 1 from public.inventory_movements where product_id = '00000000-0000-4000-8000-00000000011d')
     or not exists (
       select 1 from public.audit_logs
       where id = '00000000-0000-4000-8000-000000000124'
         and entity_type = 'product'
         and entity_id = '00000000-0000-4000-8000-00000000011c'
         and new_values @> jsonb_build_object('fixture', 'safe_admin_product_removal')
     ) then
    raise exception 'Product archival did not preserve historical records and audit evidence';
  end if;
end;
$$;

reset role;
rollback;
