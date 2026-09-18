-- Phase 10F sellability verification. Run after Phases 1-10F in a disposable
-- database only. Fixtures and all mutations are rolled back.

begin;

do $$
declare
  v_result text;
begin
  if has_function_privilege('anon', 'public.get_public_product_sellability()', 'EXECUTE') is not true
     or has_function_privilege('authenticated', 'public.get_public_product_sellability()', 'EXECUTE') is not true
     or has_function_privilege('service_role', 'public.get_public_product_sellability()', 'EXECUTE') then
    raise exception 'Public sellability RPC grants are incorrect';
  end if;
  if exists (
    select 1
    from pg_proc as procedure_row
    cross join lateral aclexplode(coalesce(procedure_row.proacl, acldefault('f', procedure_row.proowner))) as privilege_row
    where procedure_row.oid = 'public.get_public_product_sellability()'::regprocedure
      and privilege_row.grantee = 0
      and privilege_row.privilege_type = 'EXECUTE'
  ) then raise exception 'PUBLIC retains sellability RPC execution'; end if;
  if has_table_privilege('anon', 'public.inventory', 'SELECT') then
    raise exception 'Anon can directly read inventory';
  end if;

  select lower(pg_get_function_result('public.get_public_product_sellability()'::regprocedure)) into v_result;
  if v_result <> 'table(product_id uuid, is_orderable boolean)' then
    raise exception 'Public sellability DTO is too broad or incomplete';
  end if;
  if not exists (
    select 1
    from pg_proc as procedure_row
    where procedure_row.oid = 'public.get_public_product_sellability()'::regprocedure
      and procedure_row.prosecdef
      and procedure_row.provolatile = 's'
      and exists (
        select 1
        from unnest(coalesce(procedure_row.proconfig, array[]::text[])) as setting_row(value)
        where setting_row.value = 'search_path=pg_catalog, public'
      )
  ) then raise exception 'Public sellability execution boundary is unsafe'; end if;
end;
$$;

do $$
declare
  v_active_category uuid := '00000000-0000-4000-8000-0000000010f1'::uuid;
  v_inactive_category uuid := '00000000-0000-4000-8000-0000000010f2'::uuid;
begin
  insert into public.categories (id, name, slug, is_active, display_order)
  values
    (v_active_category, 'Phase 10F active', 'phase-10f-active', true, 99980),
    (v_inactive_category, 'Phase 10F inactive', 'phase-10f-inactive', false, 99981);

  insert into public.products (id, category_id, slug, name, description, base_price, price_on_request, prep_time_minutes, status, is_available, display_order)
  values
    ('00000000-0000-4000-8000-0000000010f3', v_active_category, 'phase-10f-no-inventory', 'Phase 10F no inventory', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99980),
    ('00000000-0000-4000-8000-0000000010f4', v_active_category, 'phase-10f-tracking-disabled', 'Phase 10F tracking disabled', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99981),
    ('00000000-0000-4000-8000-0000000010f5', v_active_category, 'phase-10f-positive', 'Phase 10F positive inventory', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99982),
    ('00000000-0000-4000-8000-0000000010f6', v_active_category, 'phase-10f-zero', 'Phase 10F zero inventory', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99983),
    ('00000000-0000-4000-8000-0000000010f7', v_active_category, 'phase-10f-reserved', 'Phase 10F fully reserved', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99984),
    ('00000000-0000-4000-8000-0000000010f8', v_active_category, 'phase-10f-manually-unavailable', 'Phase 10F manually unavailable', 'Disposable public sellability fixture.', 10, false, 1, 'active', false, 99985),
    ('00000000-0000-4000-8000-0000000010f9', v_active_category, 'phase-10f-price-request', 'Phase 10F price request', 'Disposable public sellability fixture.', null, true, 1, 'active', true, 99986),
    ('00000000-0000-4000-8000-0000000010fa', v_active_category, 'phase-10f-draft', 'Phase 10F draft', 'Disposable public sellability fixture.', 10, false, 1, 'draft', true, 99987),
    ('00000000-0000-4000-8000-0000000010fb', v_active_category, 'phase-10f-archived', 'Phase 10F archived', 'Disposable public sellability fixture.', 10, false, 1, 'archived', true, 99988),
    ('00000000-0000-4000-8000-0000000010fc', v_inactive_category, 'phase-10f-inactive-category', 'Phase 10F inactive category', 'Disposable public sellability fixture.', 10, false, 1, 'active', true, 99989);

  insert into public.inventory (product_id, is_tracking_enabled, quantity_on_hand, quantity_reserved)
  values
    ('00000000-0000-4000-8000-0000000010f4', false, 0, 0),
    ('00000000-0000-4000-8000-0000000010f5', true, 10, 3),
    ('00000000-0000-4000-8000-0000000010f6', true, 0, 0),
    ('00000000-0000-4000-8000-0000000010f7', true, 3, 3);
end;
$$;

set local role anon;
do $$
begin
  begin
    perform 1 from public.inventory;
    raise exception 'Anon directly read inventory rows';
  exception when insufficient_privilege then null;
  end;
  if (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f3'::uuid) is not true
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f4'::uuid) is not true
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f5'::uuid) is not true
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f6'::uuid) is not false
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f7'::uuid) is not false
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f8'::uuid) is not false
     or (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f9'::uuid) is not false
     or exists (select 1 from public.get_public_product_sellability() where product_id in ('00000000-0000-4000-8000-0000000010fa'::uuid, '00000000-0000-4000-8000-0000000010fb'::uuid, '00000000-0000-4000-8000-0000000010fc'::uuid)) then
    raise exception 'Anon sellability results are incorrect';
  end if;
end;
$$;

reset role;
set local role authenticated;
do $$
begin
  if (select is_orderable from public.get_public_product_sellability() where product_id = '00000000-0000-4000-8000-0000000010f5'::uuid) is not true then
    raise exception 'Authenticated caller could not execute public sellability RPC';
  end if;
end;
$$;

reset role;
rollback;
