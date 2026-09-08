-- Phase 3 verification. Run in the Supabase SQL editor only after applying
-- Phases 1, 2A, 2B, and 3. Replace all Auth UUID placeholders with users that
-- have the stated roles. All mutations in this script are rolled back.
--
-- Concurrent active-prefix conflicts require two sessions and cannot be proven in
-- this single-session transaction. In a disposable database, have manager session A
-- create or activate a zone with a unique test prefix without committing. Before A
-- commits, have manager session B create an active zone with the same normalized
-- prefix. B must block on the advisory lock; after A commits, B must continue and
-- fail because the active-prefix conflict is now visible.
--
-- Resolver priority and UUID ties are intentionally unreachable in valid active
-- data: same-length prefixes that both prefix-match one postcode must be identical,
-- while exact active-prefix duplicates are forbidden. The resolver nevertheless
-- retains its defensive ordering: prefix length DESC, match_priority ASC, UUID ASC.

begin;

create temporary table phase_3_test_ids (
  key text primary key,
  value uuid not null
) on commit drop;

-- Run as the SQL-editor owner to prove the singleton database constraint rather
-- than merely the browser INSERT denial.
do $$
begin
  if (select count(*) from public.business_settings) <> 1
     or not exists (select 1 from public.business_settings where id = 1) then
    raise exception 'The business-settings singleton seed is missing';
  end if;
  begin
    insert into public.business_settings (id, business_name) values (2, 'Second settings row');
    raise exception 'A second business-settings row was accepted';
  exception when check_violation then null;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);

do $$
declare
  settings_creator uuid;
  se1_zone_id uuid;
  inactive_conflict_zone_id uuid;
  se_zone_id uuid;
begin
  if not public.is_owner() then raise exception 'Owner role helper failed'; end if;

  -- Attribution is database-authored; the seeded row has no browser actor, so its
  -- original creator remains NULL while this update receives the owner as updater.
  update public.business_settings
  set business_name = 'So Yummy Foods verification',
      created_by = '00000000-0000-0000-0000-000000000000',
      updated_by = '00000000-0000-0000-0000-000000000000'
  where id = 1;
  select created_by into settings_creator from public.business_settings where id = 1;
  if settings_creator is not null
     or not exists (select 1 from public.business_settings where id = 1 and updated_by = auth.uid()) then
    raise exception 'Business-settings attribution was forgeable';
  end if;

  begin
    update public.business_settings set tax_label = 'Tax' where id = 1;
    raise exception 'Disabled tax accepted tax details';
  exception when check_violation then null;
  end;
  begin
    update public.business_settings set tax_enabled = true, tax_label = null, tax_rate_percent = 20 where id = 1;
    raise exception 'Enabled tax accepted no label';
  exception when check_violation then null;
  end;
  begin
    update public.business_settings set tax_enabled = true, tax_label = 'Tax', tax_rate_percent = 100.01 where id = 1;
    raise exception 'Out-of-range tax rate accepted';
  exception when check_violation then null;
  end;

  insert into public.delivery_zones (
    name, postcode_prefixes, delivery_fee, minimum_order, match_priority, display_order
  ) values ('SE1 verification', array[E' se\t1\n '], 3.50, 10, 5, 0)
  returning id into se1_zone_id;
  insert into phase_3_test_ids values ('se1_zone', se1_zone_id);
  if not exists (select 1 from public.delivery_zones where id = se1_zone_id and postcode_prefixes = array['SE1'] and created_by = auth.uid() and updated_by = auth.uid()) then
    raise exception 'Delivery-zone normalization or attribution failed';
  end if;

  begin
    insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order)
    values ('Duplicate within zone', array['NW 1', 'nw1'], 1, 0, 1);
    raise exception 'Duplicate normalized prefixes within a zone were accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order)
    values ('Duplicate active zone', array['SE1'], 1, 0, 1);
    raise exception 'Exact prefix conflict across active zones was accepted';
  exception when check_violation then null;
  end;

  insert into public.delivery_zones (name, is_active, postcode_prefixes, delivery_fee, match_priority, display_order)
  values ('Inactive SE1 conflict', false, array['SE1'], 1, 0, 2)
  returning id into inactive_conflict_zone_id;
  insert into phase_3_test_ids values ('inactive_conflict_zone', inactive_conflict_zone_id);
  begin
    update public.delivery_zones set is_active = true where id = inactive_conflict_zone_id;
    raise exception 'Conflicting inactive zone was activated';
  exception when check_violation then null;
  end;

  insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order)
  values ('SE verification', array['SE'], 4, 0, 3)
  returning id into se_zone_id;
  insert into phase_3_test_ids values ('se_zone', se_zone_id);
  insert into public.delivery_zones (name, is_active, postcode_prefixes, delivery_fee, match_priority, display_order)
  values ('Inactive NW1', false, array['NW1'], 2, 0, 4);

  if not exists (
    select 1 from public.audit_logs
    where entity_type = 'business_settings'
      and entity_id = '00000000-0000-0000-0000-000000000001'::uuid and action = 'update'
      and actor_user_id = auth.uid()
      and old_values is not null and new_values is not null
      and not (old_values ? 'tax_registration_number')
      and not (new_values ? 'tax_registration_number')
  ) then raise exception 'Safe business-settings audit row missing'; end if;
  if not exists (
    select 1 from public.audit_logs
    where entity_type = 'delivery_zone' and entity_id = se1_zone_id and action = 'insert'
      and actor_user_id = auth.uid() and new_values is not null
  ) then raise exception 'Delivery-zone audit row missing'; end if;

  begin
    delete from public.business_settings where id = 1;
    if found then raise exception 'Owner deleted business settings'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.delivery_zones where id = se1_zone_id;
    if found then raise exception 'Owner deleted delivery zone'; end if;
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Resolver calls are intentionally not granted to browser roles. SQL-editor owner
-- verifies longest-prefix matching, inactive exclusion, whitespace/case handling,
-- and no-match behavior. Exact active-prefix ties are invalid by design, so priority
-- and UUID tie-breakers remain defensive deterministic ordering for future use.
reset role;
do $$
declare
  se1_zone_id uuid := (select value from phase_3_test_ids where key = 'se1_zone');
begin
  if public.normalize_postcode(E'\tse1\n0aa ') <> 'SE10AA' then raise exception 'Postcode normalization failed'; end if;
  if not exists (
    select 1 from public.resolve_active_delivery_zone(E'\tsE1\n0aa ')
    where zone_id = se1_zone_id and normalized_postcode = 'SE10AA'
  ) then raise exception 'Longest active prefix was not selected'; end if;
  if exists (select 1 from public.resolve_active_delivery_zone('NW1 1AA')) then raise exception 'Inactive zone was resolved'; end if;
  if exists (select 1 from public.resolve_active_delivery_zone('ZZ9 9ZZ')) then raise exception 'No-match postcode resolved'; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare manager_zone_id uuid;
begin
  if not public.is_manager_or_owner() or public.is_owner() then raise exception 'Manager role helper failed'; end if;
  update public.business_settings set business_name = 'So Yummy Foods manager verification' where id = 1;
  if not exists (select 1 from public.business_settings where id = 1 and updated_by = auth.uid()) then raise exception 'Manager could not update business settings'; end if;
  insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order)
  values ('Manager verification', array['E1'], 2, 1, 10) returning id into manager_zone_id;
  update public.delivery_zones set delivery_fee = 2.50 where id = manager_zone_id;
  if not exists (
    select 1 from public.delivery_zones
    where id = manager_zone_id and delivery_fee = 2.50 and updated_by = auth.uid()
  ) then raise exception 'Manager delivery-zone update did not persist with attribution'; end if;
  insert into phase_3_test_ids values ('manager_zone', manager_zone_id);
  begin
    delete from public.delivery_zones where id = manager_zone_id;
    if found then raise exception 'Manager deleted delivery zone'; end if;
  exception when insufficient_privilege then null;
  end;
  begin insert into public.business_settings (id, business_name) values (1, 'Manager insert'); raise exception 'Manager inserted business settings'; exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare zone_id uuid := (select value from phase_3_test_ids where key = 'se1_zone');
begin
  if not exists (select 1 from public.business_settings where id = 1)
     or not exists (select 1 from public.delivery_zones where id = zone_id) then raise exception 'Staff read policy failed'; end if;
  update public.business_settings set business_name = 'Staff write' where id = 1;
  if found then raise exception 'Staff updated business settings'; end if;
  begin insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order) values ('Staff write', array['W1'], 1, 0, 99); raise exception 'Staff inserted delivery zone'; exception when insufficient_privilege then null; end;
  update public.delivery_zones set delivery_fee = 99 where id = zone_id;
  if found then raise exception 'Staff updated delivery zone'; end if;
  begin delete from public.business_settings where id = 1; if found then raise exception 'Staff deleted business settings'; end if; exception when insufficient_privilege then null; end;
  begin delete from public.delivery_zones where id = zone_id; if found then raise exception 'Staff deleted delivery zone'; end if; exception when insufficient_privilege then null; end;
end;
$$;

set local role anon;
do $$
begin
  begin perform 1 from public.business_settings; raise exception 'Anon read business settings'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.delivery_zones; raise exception 'Anon read delivery zones'; exception when insufficient_privilege then null; end;
  begin update public.business_settings set business_name = 'Anon write' where id = 1; raise exception 'Anon updated business settings'; exception when insufficient_privilege then null; end;
  begin insert into public.delivery_zones (name, postcode_prefixes, delivery_fee, match_priority, display_order) values ('Anon write', array['EC1'], 1, 0, 99); raise exception 'Anon inserted delivery zone'; exception when insufficient_privilege then null; end;
  begin delete from public.business_settings where id = 1; raise exception 'Anon deleted business settings'; exception when insufficient_privilege then null; end;
  begin delete from public.delivery_zones where name = 'SE1 verification'; raise exception 'Anon deleted delivery zone'; exception when insufficient_privilege then null; end;
  begin perform public.resolve_active_delivery_zone('SE1 0AA'); raise exception 'Anon executed delivery resolver'; exception when insufficient_privilege then null; end;
end;
$$;

rollback;
