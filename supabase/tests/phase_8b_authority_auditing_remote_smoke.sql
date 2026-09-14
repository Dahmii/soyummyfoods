-- Phase 8B hosted-project smoke verification. Safe to run against the hosted
-- project: only reserved disposable fixtures are created, every mutation is
-- rolled back, and no real user, profile, or authority row is touched.
--
-- The final-owner invariant is structurally inspected here because a hosted
-- project can already have real owners; see phase_8b_authority_auditing_verification.sql
-- for the exhaustive disposable-database behavioral final-owner test.

begin;

create temporary table phase_8b_ids (key text primary key, value uuid not null) on commit drop;
insert into phase_8b_ids values
  ('owner', '00000000-0000-4000-8000-0000000008b1'),
  ('manager', '00000000-0000-4000-8000-0000000008b2'),
  ('staff', '00000000-0000-4000-8000-0000000008b3'),
  ('target', '00000000-0000-4000-8000-0000000008b4'),
  ('cascade_target', '00000000-0000-4000-8000-0000000008b5');

-- profiles.id references auth.users.id. These minimal, transaction-local Auth
-- rows let the existing Auth -> profile trigger create consistent fixtures.
-- No Auth instance, identities, external Auth API, or real account is used.
do $$
declare
  v_owner uuid := '00000000-0000-4000-8000-0000000008b1'::uuid;
  v_manager uuid := '00000000-0000-4000-8000-0000000008b2'::uuid;
  v_staff uuid := '00000000-0000-4000-8000-0000000008b3'::uuid;
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
  v_cascade_target uuid := '00000000-0000-4000-8000-0000000008b5'::uuid;
begin
  if exists (
    select 1 from auth.users as auth_user
    where auth_user.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
       or auth_user.email in (
         'phase-8b-owner@example.test', 'phase-8b-manager@example.test',
         'phase-8b-staff@example.test', 'phase-8b-target@example.test',
         'phase-8b-cascade@example.test'
       )
  ) or exists (
    select 1 from public.profiles as profile_row
    where profile_row.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
  ) or exists (
    select 1 from public.user_roles as role_membership
    where role_membership.user_id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
  ) then
    raise exception 'Phase 8B reserved smoke fixtures already exist; refusing to modify them';
  end if;

  insert into auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (v_owner, 'authenticated', 'authenticated', 'phase-8b-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B smoke owner'), now(), now()),
    (v_manager, 'authenticated', 'authenticated', 'phase-8b-manager@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B smoke manager'), now(), now()),
    (v_staff, 'authenticated', 'authenticated', 'phase-8b-staff@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B smoke staff'), now(), now()),
    (v_target, 'authenticated', 'authenticated', 'phase-8b-target@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B smoke target'), now(), now()),
    (v_cascade_target, 'authenticated', 'authenticated', 'phase-8b-cascade@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B smoke cascade'), now(), now());

  if (select count(*) from public.profiles as profile_row
      where profile_row.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)) <> 5 then
    raise exception 'Auth fixture creation did not invoke the profile trigger';
  end if;
  insert into public.user_roles (user_id, role)
  values (v_owner, 'owner'), (v_manager, 'manager'), (v_staff, 'staff');
end;
$$;

-- Targeted metadata checks. Function source is inspected only for the shared
-- advisory-lock discipline and the guard condition, which catalogs do not
-- represent directly.
do $$
declare
  v_rpc_definition text;
  v_guard_definition text;
  v_lock_position integer;
  v_user_id_attnum smallint;
begin
  select attribute_row.attnum into v_user_id_attnum
  from pg_attribute as attribute_row
  where attribute_row.attrelid = 'public.user_roles'::regclass
    and attribute_row.attname = 'user_id'
    and not attribute_row.attisdropped;
  if not exists (
    select 1 from pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.user_roles'::regclass
      and constraint_row.contype = 'u'
      and array_length(constraint_row.conkey, 1) = 1
      and constraint_row.conkey[1] = v_user_id_attnum
  ) then raise exception 'One-role-per-user uniqueness is missing'; end if;
  if has_table_privilege('anon', 'public.user_roles', 'INSERT')
     or has_table_privilege('authenticated', 'public.user_roles', 'INSERT')
     or has_table_privilege('anon', 'public.user_roles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.user_roles', 'UPDATE')
     or has_table_privilege('anon', 'public.user_roles', 'DELETE')
     or has_table_privilege('authenticated', 'public.user_roles', 'DELETE') then
    raise exception 'A browser role retains direct role-write privileges';
  end if;
  if has_function_privilege('anon', 'public.set_user_role(uuid,public.app_role)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.set_user_role(uuid,public.app_role)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.set_user_role(uuid,public.app_role)', 'EXECUTE') then
    raise exception 'Role-transition RPC grants are incorrect';
  end if;
  if not exists (
    select 1 from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'public.user_roles'::regclass
      and trigger_row.tgname = 'user_roles_prevent_final_owner_removal_before_mutation'
      and trigger_row.tgfoid = 'public.prevent_final_owner_removal()'::regprocedure
      and not trigger_row.tgisinternal
      and (trigger_row.tgtype::integer & 1) = 1
      and (trigger_row.tgtype::integer & 2) = 2
      and (trigger_row.tgtype::integer & 4) = 0
      and (trigger_row.tgtype::integer & 8) = 8
      and (trigger_row.tgtype::integer & 16) = 16
  ) then raise exception 'Final-owner BEFORE UPDATE OR DELETE row trigger is incorrect'; end if;
  if not exists (
    select 1 from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'public.user_roles'::regclass
      and trigger_row.tgname = 'user_roles_write_audit_after_mutation'
      and trigger_row.tgfoid = 'public.write_user_role_audit_log()'::regprocedure
      and not trigger_row.tgisinternal
      and (trigger_row.tgtype::integer & 1) = 1
      and (trigger_row.tgtype::integer & 2) = 0
      and (trigger_row.tgtype::integer & 4) = 4
      and (trigger_row.tgtype::integer & 8) = 8
      and (trigger_row.tgtype::integer & 16) = 16
  ) then raise exception 'Role audit AFTER row trigger is incorrect'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.payments'::regclass
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'r'
      and source_column.attname = 'reconciliation_resolved_by' and target_column.attname = 'id'
  ) then raise exception 'payments.reconciliation_resolved_by must restrict profile deletion'; end if;
  select pg_get_functiondef('public.set_user_role(uuid,public.app_role)'::regprocedure) into v_rpc_definition;
  select pg_get_functiondef('public.prevent_final_owner_removal()'::regprocedure) into v_guard_definition;
  v_lock_position := position('pg_advisory_xact_lock' in lower(v_rpc_definition));
  if v_lock_position = 0
     or position('if not public.is_owner()' in lower(v_rpc_definition)) = 0
     or position('if not public.is_owner()' in lower(v_rpc_definition)) > v_lock_position
     or position('if not public.is_owner()' in substring(lower(v_rpc_definition) from v_lock_position + 1)) = 0
     or position('hashtext(''public.set_user_role:authority'')' in lower(v_rpc_definition)) = 0
     or position('hashtext(''public.set_user_role:authority'')' in lower(v_guard_definition)) = 0
     or position('pg_advisory_xact_lock' in lower(v_guard_definition)) = 0
     or position('pg_advisory_xact_lock' in lower(v_guard_definition)) > position('select count(*) into v_owner_count' in lower(v_guard_definition))
     or position('old.role <> ''owner''::public.app_role' in lower(v_guard_definition)) = 0
     or position('tg_op = ''update'' and new.role = ''owner''::public.app_role' in lower(v_guard_definition)) = 0
     or position('v_owner_count <= 1' in lower(v_guard_definition)) = 0 then
    raise exception 'Final-owner advisory-lock discipline is incorrect';
  end if;
end;
$$;

-- Browser contexts receive only literal fixture identifiers; they never read
-- the privileged temporary fixture table.
set local role anon;
do $$ begin
  begin perform public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'staff'); raise exception 'Anon changed a role'; exception when insufficient_privilege then null; end;
end; $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
do $$ begin
  begin perform public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'staff'); raise exception 'Unauthenticated caller changed a role'; exception when insufficient_privilege then null; end;
end; $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b2', true);
do $$ begin
  begin perform public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'staff'); raise exception 'Manager changed a role'; exception when insufficient_privilege then null; end;
end; $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b3', true);
do $$ begin
  if not public.has_role('staff'::public.app_role) then raise exception 'Staff role helper failed'; end if;
  begin perform public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'staff'); raise exception 'Staff changed a role'; exception when insufficient_privilege then null; end;
  begin insert into public.user_roles(user_id, role) values ('00000000-0000-4000-8000-0000000008b4', 'staff'); raise exception 'Authenticated direct INSERT succeeded'; exception when insufficient_privilege then null; end;
  begin update public.user_roles set role = 'manager' where user_id = auth.uid(); raise exception 'Authenticated direct UPDATE succeeded'; exception when insufficient_privilege then null; end;
  begin delete from public.user_roles where user_id = auth.uid(); raise exception 'Authenticated direct DELETE succeeded'; exception when insufficient_privilege then null; end;
end; $$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b1', true);
do $$
declare v_result record;
begin
  begin perform public.set_user_role('00000000-0000-4000-8000-0000000008b1', 'manager'); raise exception 'Owner changed their own role'; exception when insufficient_privilege then null; end;
  select * into v_result from public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'staff');
  if not v_result.changed or v_result.previous_role is not null or v_result.new_role <> 'staff' then raise exception 'Owner could not assign staff'; end if;
  select * into v_result from public.set_user_role('00000000-0000-4000-8000-0000000008b4', 'manager');
  if not v_result.changed or v_result.previous_role <> 'staff' or v_result.new_role <> 'manager' then raise exception 'Owner could not replace a role'; end if;
  select * into v_result from public.set_user_role('00000000-0000-4000-8000-0000000008b4', null);
  if not v_result.changed or v_result.previous_role <> 'manager' or v_result.new_role is not null then raise exception 'Owner could remove a role'; end if;
end;
$$;

-- Privileged state assertions and fixture-only direct writes resume after every
-- browser test. These assertions never query or mutate real authority rows.
reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_owner uuid := '00000000-0000-4000-8000-0000000008b1'::uuid;
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
  v_cascade_target uuid := '00000000-0000-4000-8000-0000000008b5'::uuid;
begin
  if (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_target and action = 'insert'
      and new_values @> jsonb_build_object('role', 'staff', 'actor_user_id_snapshot', v_owner, 'origin', 'authenticated_admin')) <> 1
     or (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_target and action = 'update'
      and old_values @> jsonb_build_object('role', 'staff') and new_values @> jsonb_build_object('role', 'manager', 'actor_user_id_snapshot', v_owner)) <> 1
     or (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_target and action = 'delete'
      and old_values @> jsonb_build_object('role', 'manager', 'actor_user_id_snapshot', v_owner)) <> 1 then
    raise exception 'Trusted role transitions did not create exactly one audit row each';
  end if;

  insert into public.user_roles(user_id, role) values (v_cascade_target, 'staff');
  update public.user_roles set role = 'manager' where user_id = v_cascade_target;
  delete from public.user_roles where user_id = v_cascade_target;
  if (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_cascade_target and action = 'insert') <> 1
     or (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_cascade_target and action = 'update') <> 1
     or (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_cascade_target and action = 'delete') <> 1 then
    raise exception 'Privileged fixture-only role writes were not audited exactly once';
  end if;

  insert into public.user_roles(user_id, role) values (v_cascade_target, 'staff');
  delete from public.profiles where id = v_cascade_target;
  if exists (select 1 from public.user_roles where user_id = v_cascade_target)
     or (select count(*) from public.audit_logs where entity_type = 'user_role' and entity_id = v_cascade_target
         and action = 'delete' and actor_user_id is null
         and old_values @> jsonb_build_object('role', 'staff', 'origin', 'system')
     ) <> 1 then raise exception 'Fixture profile cascade was not recorded exactly once'; end if;
end;
$$;

reset role;
rollback;
