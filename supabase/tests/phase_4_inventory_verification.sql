-- Phase 4 verification. Run after Phases 1-4 in a disposable database.
-- Replace the role UUID placeholders. Every mutation is rolled back.
--
-- Concurrency requires two sessions and cannot be proven in this transaction:
-- start with a tracked row at 3. Session A calls adjust_inventory(..., -2, ...)
-- and holds its transaction open. Session B calls the same deduction and must block
-- at SELECT ... FOR UPDATE. After A commits, B must read 1, fail the negative-stock
-- validation, and create no movement. Future Phase 5 multi-product operations must
-- lock inventory rows in deterministic inventory/product-ID order.
--
-- Additional two-session disposable-database tests:
-- 1. First configuration: A configures a product and holds its transaction. B
--    configures the same product and blocks on the product lock. After A commits,
--    B proceeds: exactly one inventory row exists, B's later values are current,
--    and both attributable configuration events are audited when values changed.
-- 2. Adjustment versus disable: the session which first reaches the inventory row
--    completes. The second then observes its committed state; an adjustment that
--    observes disabled tracking fails and creates no movement.
-- 3. Staff versus archive: when staff has the product FOR SHARE lock first, archive
--    blocks until the movement commits. If archive commits first, staff later locks
--    the product, sees archived status, fails, and creates no movement.
-- 4. Browser/manual check: clear Quantity change in the inventory form and submit.
--    It must remain blank and show "Quantity change is required." Entered zero must
--    still show the separate invalid-zero error. SQL cannot test React input state.

begin;

create temporary table phase_4_ids (key text primary key, value uuid not null) on commit drop;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);

do $$
declare
  category_id uuid;
  test_product_id uuid;
  test_inventory_id uuid;
  archived_product_id uuid;
  archived_inventory_id uuid;
  active_product_id uuid;
  active_inventory_id uuid;
  por_product_id uuid;
  before_count integer;
begin
  if not public.is_owner() then raise exception 'Owner role helper failed'; end if;
  select id into category_id from public.categories order by display_order limit 1;
  if category_id is null then raise exception 'A seeded category is required'; end if;
  insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order)
  values (category_id, 'phase-4-inventory-test', 'Phase 4 inventory test', 'Draft inventory verification product.', 1, 1, 'draft', 9999)
  returning id into test_product_id;
  insert into phase_4_ids values ('draft_product', test_product_id);
  insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order)
  values (category_id, 'phase-4-archived-test', 'Phase 4 archived test', 'Archived inventory verification product.', 1, 1, 'archived', 10000)
  returning id into archived_product_id;
  select id into archived_inventory_id from public.configure_product_inventory(archived_product_id, true, null);
  insert into phase_4_ids values ('archived_product', archived_product_id), ('archived_inventory', archived_inventory_id);

  select id into active_product_id from public.products where status = 'active' order by display_order limit 1;
  if active_product_id is null then raise exception 'An active seeded product is required'; end if;
  select id into active_inventory_id from public.configure_product_inventory(active_product_id, true, null);
  insert into phase_4_ids values ('active_product', active_product_id), ('active_inventory', active_inventory_id);
  select id into por_product_id from public.products where slug = 'coconut-rice';
  if por_product_id is null then raise exception 'Price-on-request product seed missing'; end if;
  perform public.configure_product_inventory(por_product_id, true, null);

  select id into test_inventory_id from public.configure_product_inventory(test_product_id, true, 0);
  insert into phase_4_ids values ('draft_inventory', test_inventory_id);
  if not exists (select 1 from public.inventory where id = test_inventory_id and quantity_on_hand = 0 and is_tracking_enabled and low_stock_threshold = 0 and created_by = auth.uid() and updated_by = auth.uid()) then
    raise exception 'Inventory configuration, zero quantity, or attribution failed';
  end if;
  if not exists (select 1 from public.audit_logs where entity_type = 'inventory' and entity_id = test_inventory_id and action = 'insert' and actor_user_id = auth.uid()) then
    raise exception 'Initial inventory configuration audit row missing';
  end if;
  begin perform public.configure_product_inventory(test_product_id, true, -1); raise exception 'Negative threshold accepted'; exception when check_violation then null; end;
  begin update public.inventory set quantity_on_hand = -1 where id = test_inventory_id; raise exception 'Direct negative inventory update accepted'; exception when insufficient_privilege then null; end;

  perform public.adjust_inventory(test_inventory_id, 'stock_added', 5, null);
  if not exists (select 1 from public.inventory_movements as movement where movement.inventory_id = test_inventory_id and movement.product_id = test_product_id and movement.movement_type = 'stock_added' and movement.quantity_delta = 5 and movement.quantity_before = 0 and movement.quantity_after = 5 and movement.actor_user_id = auth.uid()) then
    raise exception 'Stock-added ledger row is incorrect';
  end if;
  select count(*) into before_count from public.audit_logs where entity_type = 'inventory' and entity_id = test_inventory_id;
  perform public.adjust_inventory(test_inventory_id, 'manual_adjustment', -1, 'Counted one less portion');
  if not exists (select 1 from public.inventory_movements as movement where movement.inventory_id = test_inventory_id and movement.movement_type = 'manual_adjustment' and movement.quantity_before = 5 and movement.quantity_after = 4 and movement.note = 'Counted one less portion') then raise exception 'Manager correction failed'; end if;
  if (select count(*) from public.audit_logs where entity_type = 'inventory' and entity_id = test_inventory_id) <> before_count then raise exception 'Quantity movement was unnecessarily duplicated into audit logs'; end if;
  begin perform public.adjust_inventory(test_inventory_id, 'waste', -1, ' '); raise exception 'Blank waste note accepted'; exception when check_violation then null; end;
  begin perform public.adjust_inventory(test_inventory_id, 'stock_added', -1, null); raise exception 'Negative stock-added movement accepted'; exception when check_violation then null; end;
  begin perform public.adjust_inventory(test_inventory_id, 'waste', 1, 'Wrong direction'); raise exception 'Positive waste movement accepted'; exception when check_violation then null; end;
  begin perform public.adjust_inventory(test_inventory_id, 'order_deduction', -1, null); raise exception 'Reserved order movement accepted through browser RPC'; exception when insufficient_privilege then null; end;
  begin perform public.adjust_inventory(test_inventory_id, 'order_restock', 1, null); raise exception 'Reserved order-restock movement accepted through browser RPC'; exception when insufficient_privilege then null; end;
  select count(*) into before_count from public.inventory_movements as movement where movement.inventory_id = test_inventory_id;
  begin perform public.adjust_inventory(test_inventory_id, 'waste', -99, 'Too much'); raise exception 'Over-deduction accepted'; exception when check_violation then null; end;
  if (select quantity_on_hand from public.inventory where id = test_inventory_id) <> 4 or (select count(*) from public.inventory_movements as movement where movement.inventory_id = test_inventory_id) <> before_count then raise exception 'Failed over-deduction changed inventory or ledger'; end if;

  perform public.configure_product_inventory(test_product_id, false, null);
  if not exists (select 1 from public.inventory where id = test_inventory_id and not is_tracking_enabled and quantity_on_hand = 4 and low_stock_threshold is null) then raise exception 'Disable tracking did not retain quantity'; end if;
  if not exists (select 1 from public.audit_logs where entity_type = 'inventory' and entity_id = test_inventory_id and action = 'update' and actor_user_id = auth.uid()) then raise exception 'Inventory configuration update audit row missing'; end if;
  begin perform public.adjust_inventory(test_inventory_id, 'stock_added', 1, null); raise exception 'Disabled tracking accepted adjustment'; exception when check_violation then null; end;
  perform public.configure_product_inventory(test_product_id, true, null);
  perform public.configure_product_inventory(test_product_id, true, 3);
  if not exists (
    select 1 from public.audit_logs
    where entity_type = 'inventory' and entity_id = test_inventory_id and action = 'update'
      and actor_user_id = auth.uid()
      and old_values ->> 'low_stock_threshold' is null
      and new_values ->> 'low_stock_threshold' = '3'
  ) then raise exception 'Threshold-only configuration audit row missing'; end if;
  begin delete from public.inventory where id = test_inventory_id; raise exception 'Direct inventory delete accepted'; exception when insufficient_privilege then null; end;
  begin insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after) values (test_inventory_id, test_product_id, 'stock_added', 1, 4, 5); raise exception 'Owner forged a movement'; exception when insufficient_privilege then null; end;
  begin update public.inventory_movements set note = 'forged' where inventory_id = test_inventory_id; raise exception 'Movement update accepted'; exception when insufficient_privilege then null; end;
  begin delete from public.inventory_movements where inventory_id = test_inventory_id; raise exception 'Movement delete accepted'; exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare draft_inventory_id uuid := (select value from phase_4_ids where key = 'draft_inventory');
declare archived_inventory_id uuid := (select value from phase_4_ids where key = 'archived_inventory');
begin
  if not public.is_manager_or_owner() or public.is_owner() then raise exception 'Manager role helper failed'; end if;
  perform public.configure_product_inventory((select value from phase_4_ids where key = 'draft_product'), true, 2);
  perform public.adjust_inventory(draft_inventory_id, 'waste', -1, 'Draft reconciliation');
  perform public.adjust_inventory(archived_inventory_id, 'stock_added', 1, null);
  if not exists (select 1 from public.inventory_movements where inventory_id = draft_inventory_id and actor_user_id = auth.uid() and movement_type = 'waste') then raise exception 'Manager draft reconciliation failed'; end if;
  begin insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after) values (draft_inventory_id, (select value from phase_4_ids where key = 'draft_product'), 'stock_added', 1, 0, 1); raise exception 'Manager forged a movement'; exception when insufficient_privilege then null; end;
  begin update public.inventory_movements set note = 'forged' where inventory_id = draft_inventory_id; raise exception 'Manager updated a movement'; exception when insufficient_privilege then null; end;
  begin delete from public.inventory_movements where inventory_id = draft_inventory_id; raise exception 'Manager deleted a movement'; exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare active_product_id uuid := (select value from phase_4_ids where key = 'active_product');
declare active_inventory_id uuid := (select value from phase_4_ids where key = 'active_inventory');
declare draft_inventory_id uuid := (select value from phase_4_ids where key = 'draft_inventory');
declare archived_inventory_id uuid := (select value from phase_4_ids where key = 'archived_inventory');
begin
  if not public.is_staff_or_above() or public.is_manager_or_owner() then raise exception 'Staff role helper failed'; end if;
  if not exists (select 1 from public.inventory) or not exists (select 1 from public.inventory_movements) then raise exception 'Staff read policies failed'; end if;
  perform public.adjust_inventory(active_inventory_id, 'stock_added', 1, null);
  perform public.adjust_inventory(active_inventory_id, 'waste', -1, 'Staff waste');
  begin perform public.adjust_inventory(active_inventory_id, 'manual_adjustment', 1, 'Staff correction'); raise exception 'Staff correction accepted'; exception when insufficient_privilege then null; end;
  begin perform public.adjust_inventory(draft_inventory_id, 'stock_added', 1, null); raise exception 'Staff changed draft inventory'; exception when insufficient_privilege then null; end;
  begin perform public.adjust_inventory(archived_inventory_id, 'stock_added', 1, null); raise exception 'Staff changed archived inventory'; exception when insufficient_privilege then null; end;
  begin perform public.configure_product_inventory(active_product_id, false, null); raise exception 'Staff configured inventory'; exception when insufficient_privilege then null; end;
  begin insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after) values (active_inventory_id, active_product_id, 'stock_added', 1, 0, 1); raise exception 'Staff forged a movement'; exception when insufficient_privilege then null; end;
end;
$$;

set local role anon;
do $$
begin
  begin perform 1 from public.inventory; raise exception 'Anon read inventory'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.inventory_movements; raise exception 'Anon read movements'; exception when insufficient_privilege then null; end;
  begin perform public.adjust_inventory('00000000-0000-0000-0000-000000000000', 'stock_added', 1, null); raise exception 'Anon executed adjustment RPC'; exception when insufficient_privilege then null; end;
  begin perform public.configure_product_inventory('00000000-0000-0000-0000-000000000000', true, null); raise exception 'Anon executed configuration RPC'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
do $$
declare
  test_product_id uuid := (select value from phase_4_ids where key = 'draft_product');
  test_inventory_id uuid := (select value from phase_4_ids where key = 'draft_inventory');
begin
  if has_function_privilege('anon', 'public.adjust_inventory(uuid,text,integer,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.configure_product_inventory(uuid,boolean,integer)', 'EXECUTE') then
    raise exception 'Anon received Phase 4 RPC execute privilege';
  end if;
  if not has_function_privilege('authenticated', 'public.adjust_inventory(uuid,text,integer,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.configure_product_inventory(uuid,boolean,integer)', 'EXECUTE') then
    raise exception 'Authenticated RPC grants are missing';
  end if;
  if exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) as privilege
    where procedure.oid in (
      'public.adjust_inventory(uuid,text,integer,text)'::regprocedure,
      'public.configure_product_inventory(uuid,boolean,integer)'::regprocedure
    ) and privilege.grantee = 0 and privilege.privilege_type = 'EXECUTE'
  ) then raise exception 'PUBLIC retained Phase 4 RPC execute privilege'; end if;
  begin
    insert into public.inventory (product_id) values (test_product_id);
    raise exception 'Duplicate inventory row accepted';
  exception when unique_violation then null;
  end;
  begin
    insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after)
    values (test_inventory_id, '00000000-0000-0000-0000-000000000000', 'stock_added', 1, 0, 1);
    raise exception 'Movement accepted mismatched product identity';
  exception when foreign_key_violation then null;
  end;
  if not exists (select 1 from public.products where slug = 'coconut-rice') then raise exception 'Price-on-request product seed missing'; end if;
  -- POR products are ordinary sellable portions for inventory purposes; no pricing fields are read by these RPCs.
  if exists (select 1 from pg_policies where tablename in ('inventory', 'inventory_movements') and qual::text like '%user_roles%') then raise exception 'Inventory RLS must use role helpers, not recursive user_roles policies'; end if;
end;
$$;

rollback;
