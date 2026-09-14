-- Phase 8B exhaustive integration verification. Run only against a disposable
-- local/test database that this script owns. It behaviorally exercises the
-- global final-owner invariant and must not run against the hosted project.
-- The setup creates five disposable Auth users; all rows are rolled back.

begin;

create temporary table phase_8b_ids (key text primary key, value uuid not null) on commit drop;
insert into phase_8b_ids values
  ('owner', '00000000-0000-4000-8000-0000000008b1'),
  ('manager', '00000000-0000-4000-8000-0000000008b2'),
  ('staff', '00000000-0000-4000-8000-0000000008b3'),
  ('target', '00000000-0000-4000-8000-0000000008b4'),
  ('cascade_target', '00000000-0000-4000-8000-0000000008b5');

-- Refuse to touch a reserved identity if it somehow already exists. This keeps
-- the fixture setup from modifying a real user or a leftover manual fixture.
do $$
declare
  v_owner uuid := (select value from phase_8b_ids where key = 'owner');
  v_manager uuid := (select value from phase_8b_ids where key = 'manager');
  v_staff uuid := (select value from phase_8b_ids where key = 'staff');
  v_target uuid := (select value from phase_8b_ids where key = 'target');
  v_cascade_target uuid := (select value from phase_8b_ids where key = 'cascade_target');
begin
  if exists (
    select 1
    from auth.users as auth_user
    where auth_user.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
       or auth_user.email in (
         'phase-8b-owner@example.test',
         'phase-8b-manager@example.test',
         'phase-8b-staff@example.test',
         'phase-8b-target@example.test',
         'phase-8b-cascade@example.test'
       )
  ) or exists (
    select 1
    from public.profiles as profile_row
    where profile_row.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
  ) or exists (
    select 1
    from public.user_roles as role_membership
    where role_membership.user_id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)
  ) then
    raise exception 'Phase 8B reserved fixture identities already exist; refusing to modify them';
  end if;

  -- profiles.id has an Auth foreign key, so minimal auth.users rows are still
  -- necessary. Omit instance_id: it is not application authority state and no
  -- instance lookup is needed. No Auth identity rows or Auth API behavior are
  -- needed for this application-table verification.
  insert into auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) values
    (v_owner, 'authenticated', 'authenticated', 'phase-8b-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B owner fixture'), now(), now()),
    (v_manager, 'authenticated', 'authenticated', 'phase-8b-manager@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B manager fixture'), now(), now()),
    (v_staff, 'authenticated', 'authenticated', 'phase-8b-staff@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B staff fixture'), now(), now()),
    (v_target, 'authenticated', 'authenticated', 'phase-8b-target@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B target fixture'), now(), now()),
    (v_cascade_target, 'authenticated', 'authenticated', 'phase-8b-cascade@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('display_name', 'Phase 8B cascade fixture'), now(), now());

  if (select count(*) from public.profiles as profile_row
      where profile_row.id in (v_owner, v_manager, v_staff, v_target, v_cascade_target)) <> 5 then
    raise exception 'Auth fixture creation did not invoke the profile trigger';
  end if;

  insert into public.user_roles (user_id, role)
  values
    (v_owner, 'owner'),
    (v_manager, 'manager'),
    (v_staff, 'staff');
end;
$$;

-- Catalog checks cover wiring and permission regressions. The disposable
-- assertions below exercise the final-owner behavior itself.
do $$
declare
  v_definition text;
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
  ) then
    raise exception 'One-role-per-user uniqueness is missing';
  end if;
  if exists (
    select 1 from pg_policies as policy_row
    where policy_row.schemaname = 'public'
      and policy_row.tablename = 'user_roles'
      and policy_row.policyname = 'user_roles_owner_manage'
  ) then
    raise exception 'Obsolete direct role-write policy remains';
  end if;
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

  select pg_get_functiondef('public.set_user_role(uuid,public.app_role)'::regprocedure)
    into v_definition;
  v_lock_position := position('pg_advisory_xact_lock' in lower(v_definition));
  if v_lock_position = 0
     or position('if not public.is_owner()' in lower(v_definition)) = 0
     or position('if not public.is_owner()' in lower(v_definition)) > v_lock_position
     or position('if not public.is_owner()' in substring(lower(v_definition) from v_lock_position + 1)) = 0
     or v_lock_position > position('select count(*) into v_owner_count' in lower(v_definition))
     or position('hashtext(''public.set_user_role:authority'')' in lower(v_definition)) = 0
     or position('final owner cannot be demoted or removed' in lower(v_definition)) = 0 then
    raise exception 'Role-transition authorization/locking sequence is incorrect';
  end if;
  if not exists (
    select 1
    from pg_trigger as guard_trigger
    join pg_trigger as audit_trigger
      on audit_trigger.tgrelid = guard_trigger.tgrelid
    where guard_trigger.tgrelid = 'public.user_roles'::regclass
      and guard_trigger.tgname = 'user_roles_prevent_final_owner_removal_before_mutation'
      and guard_trigger.tgfoid = 'public.prevent_final_owner_removal()'::regprocedure
      and not guard_trigger.tgisinternal
      and (guard_trigger.tgtype::integer & 1) = 1
      and (guard_trigger.tgtype::integer & 2) = 2
      and (guard_trigger.tgtype::integer & 4) = 0
      and (guard_trigger.tgtype::integer & 8) = 8
      and (guard_trigger.tgtype::integer & 16) = 16
      and audit_trigger.tgname = 'user_roles_write_audit_after_mutation'
      and audit_trigger.tgfoid = 'public.write_user_role_audit_log()'::regprocedure
      and not audit_trigger.tgisinternal
      and (audit_trigger.tgtype::integer & 1) = 1
      and (audit_trigger.tgtype::integer & 2) = 0
      and (audit_trigger.tgtype::integer & 64) = 0
      and (audit_trigger.tgtype::integer & 4) = 4
      and (audit_trigger.tgtype::integer & 8) = 8
      and (audit_trigger.tgtype::integer & 16) = 16
  ) then
    raise exception 'Final-owner guard/Audit trigger ordering is incorrect';
  end if;
  select pg_get_functiondef('public.prevent_final_owner_removal()'::regprocedure)
    into v_guard_definition;
  if position('pg_advisory_xact_lock' in lower(v_guard_definition)) = 0
     or position('pg_advisory_xact_lock' in lower(v_guard_definition)) > position('select count(*) into v_owner_count' in lower(v_guard_definition))
     or position('hashtext(''public.set_user_role:authority'')' in lower(v_guard_definition)) = 0
     or position('old.role <> ''owner''::public.app_role' in lower(v_guard_definition)) = 0
     or position('tg_op = ''update'' and new.role = ''owner''::public.app_role' in lower(v_guard_definition)) = 0
     or position('v_owner_count <= 1' in lower(v_guard_definition)) = 0
     or position('final owner cannot be demoted or removed' in lower(v_guard_definition)) = 0 then
    raise exception 'Database-level final-owner guard structure is incorrect';
  end if;

  if not exists (
    select 1
    from pg_constraint as constraint_row
    join pg_attribute as source_column
      on source_column.attrelid = constraint_row.conrelid
      and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column
      on target_column.attrelid = constraint_row.confrelid
      and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.user_roles'::regclass
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.confdeltype = 'c'
      and source_column.attname = 'user_id'
      and target_column.attname = 'id'
  ) then raise exception 'user_roles.user_id no longer cascades from profiles.id'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.audit_logs'::regclass and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'n'
      and source_column.attname = 'actor_user_id' and target_column.attname = 'id'
  ) then raise exception 'audit_logs.actor_user_id deletion behavior changed'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.order_status_history'::regclass and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'n'
      and source_column.attname = 'actor_user_id' and target_column.attname = 'id'
  ) then raise exception 'order_status_history.actor_user_id deletion behavior changed'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.inventory_movements'::regclass and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'n'
      and source_column.attname = 'actor_user_id' and target_column.attname = 'id'
  ) then raise exception 'inventory_movements.actor_user_id deletion behavior changed'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.payments'::regclass and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'r'
      and source_column.attname = 'reconciliation_resolved_by' and target_column.attname = 'id'
  ) then raise exception 'payments.reconciliation_resolved_by must restrict profile deletion'; end if;
end;
$$;

-- The disposable targets were created above and intentionally begin without an
-- application role, avoiding any modification of a real user role.
do $$
declare
  v_target uuid := (select value from phase_8b_ids where key = 'target');
  v_cascade_target uuid := (select value from phase_8b_ids where key = 'cascade_target');
begin
  if (select count(*) from phase_8b_ids) <> 5
     or (select count(distinct value) from phase_8b_ids) <> 5 then
    raise exception 'Phase 8B verification UUIDs must identify five distinct users';
  end if;
  if not exists (
    select 1 from public.user_roles as role_membership
    where role_membership.user_id = (select value from phase_8b_ids where key = 'owner')
      and role_membership.role = 'owner'::public.app_role
  ) or not exists (
    select 1 from public.user_roles as role_membership
    where role_membership.user_id = (select value from phase_8b_ids where key = 'manager')
      and role_membership.role = 'manager'::public.app_role
  ) or not exists (
    select 1 from public.user_roles as role_membership
    where role_membership.user_id = (select value from phase_8b_ids where key = 'staff')
      and role_membership.role = 'staff'::public.app_role
  ) then
    raise exception 'Phase 8B verification requires owner, manager, and staff test roles';
  end if;
  if not exists (select 1 from public.profiles where id = v_target)
     or not exists (select 1 from public.profiles where id = v_cascade_target) then
    raise exception 'Phase 8B requires two disposable Auth/profile test users';
  end if;
  if exists (select 1 from public.user_roles where user_id in (v_target, v_cascade_target)) then
    raise exception 'Phase 8B disposable test users must start without application roles';
  end if;
end;
$$;

-- Privileged setup proves the unique constraint itself rejects duplicate roles.
do $$
declare
  v_target uuid := (select value from phase_8b_ids where key = 'target');
begin
  insert into public.user_roles(user_id, role) values (v_target, 'staff');
  begin
    insert into public.user_roles(user_id, role) values (v_target, 'manager');
    raise exception 'Duplicate application role was accepted';
  exception when unique_violation then null;
  end;
  delete from public.user_roles where user_id = v_target;
end;
$$;

set local role anon;
do $$
declare v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
begin
  begin perform public.set_user_role(v_target, 'staff'); raise exception 'Anon changed a role'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
begin
  begin perform public.set_user_role(v_target, 'staff'); raise exception 'Unauthenticated caller changed a role'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b2', true);
do $$
declare v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
begin
  begin perform public.set_user_role(v_target, 'staff'); raise exception 'Manager changed a role'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b3', true);
do $$
declare
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
begin
  begin perform public.set_user_role(v_target, 'staff'); raise exception 'Staff changed a role'; exception when insufficient_privilege then null; end;
  if not exists (select 1 from public.user_roles where user_id = auth.uid()) then
    raise exception 'Required self-role SELECT behavior was lost';
  end if;
  begin insert into public.user_roles(user_id, role) values (v_target, 'staff'); raise exception 'Authenticated direct INSERT succeeded'; exception when insufficient_privilege then null; end;
  begin update public.user_roles set role = 'manager' where user_id = auth.uid(); raise exception 'Authenticated direct UPDATE succeeded'; exception when insufficient_privilege then null; end;
  begin delete from public.user_roles where user_id = auth.uid(); raise exception 'Authenticated direct DELETE succeeded'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b1', true);
do $$
declare
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
  v_owner uuid := '00000000-0000-4000-8000-0000000008b1'::uuid;
  v_result record;
begin
  if not public.has_role('owner'::public.app_role) then raise exception 'Owner helper stopped recognizing the owner'; end if;
  begin perform public.set_user_role(v_owner, 'manager'); raise exception 'Owner changed their own role'; exception when insufficient_privilege then null; end;

  select * into v_result from public.set_user_role(v_target, 'staff');
  if not v_result.changed or v_result.previous_role is not null or v_result.new_role <> 'staff' then
    raise exception 'Owner could not assign staff';
  end if;
end;
$$;

-- Internal assertions use the privileged verification context, never a browser
-- role. The RPC must own granted_by/granted_at and the audit trigger owns audit.
reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_target uuid := (select value from phase_8b_ids where key = 'target');
  v_owner uuid := (select value from phase_8b_ids where key = 'owner');
begin
  if not exists (
    select 1 from public.user_roles as role_membership
    where role_membership.user_id = v_target
      and role_membership.role = 'staff'
      and role_membership.granted_by = v_owner
      and role_membership.granted_at is not null
  ) then raise exception 'Role assignment provenance was not set by the trusted RPC'; end if;
  if (select count(*) from public.audit_logs as audit_row
      where audit_row.entity_type = 'user_role' and audit_row.entity_id = v_target
        and audit_row.action = 'insert'
        and audit_row.new_values @> jsonb_build_object('target_user_id', v_target, 'role', 'staff', 'actor_user_id_snapshot', v_owner, 'origin', 'authenticated_admin')) <> 1 then
    raise exception 'Role assignment did not create exactly one actor-attributed audit row';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b1', true);
do $$
declare
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
  v_result record;
begin
  select * into v_result from public.set_user_role(v_target, 'manager');
  if not v_result.changed or v_result.previous_role <> 'staff' or v_result.new_role <> 'manager' then
    raise exception 'Owner could not replace a role';
  end if;
  select * into v_result from public.set_user_role(v_target, null);
  if not v_result.changed or v_result.previous_role <> 'manager' or v_result.new_role is not null then
    raise exception 'Owner could not remove a non-final-owner role';
  end if;
  select * into v_result from public.set_user_role(v_target, 'owner');
  if not v_result.changed or v_result.new_role <> 'owner' then
    raise exception 'Owner could not assign another owner';
  end if;
  select * into v_result from public.set_user_role(v_target, null);
  if not v_result.changed or v_result.previous_role <> 'owner' or v_result.new_role is not null then
    raise exception 'Owner could not remove a non-final owner';
  end if;
  select * into v_result from public.set_user_role(v_target, null);
  if v_result.changed then raise exception 'No-op role removal generated a change'; end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_target uuid := (select value from phase_8b_ids where key = 'target');
  v_owner uuid := (select value from phase_8b_ids where key = 'owner');
begin
  if (select count(*) from public.audit_logs as audit_row
      where audit_row.entity_type = 'user_role' and audit_row.entity_id = v_target
        and audit_row.action = 'update'
        and audit_row.old_values @> jsonb_build_object('target_user_id', v_target, 'role', 'staff')
        and audit_row.new_values @> jsonb_build_object('target_user_id', v_target, 'role', 'manager', 'actor_user_id_snapshot', v_owner)) <> 1 then
    raise exception 'Role replacement audit evidence is incorrect';
  end if;
  if (select count(*) from public.audit_logs as audit_row
      where audit_row.entity_type = 'user_role' and audit_row.entity_id = v_target
        and audit_row.action = 'delete'
        and audit_row.old_values @> jsonb_build_object('target_user_id', v_target, 'role', 'owner', 'actor_user_id_snapshot', v_owner)) <> 1 then
    raise exception 'Role removal audit evidence is incorrect';
  end if;
  if exists (select 1 from public.user_roles where user_id = v_target) then
    raise exception 'Removed application access remains';
  end if;
end;
$$;

-- Create a second owner through the trusted path. This disposable database is
-- owned by the test, so the direct writes below can behaviorally prove both
-- non-final and final-owner branches of the database-level guard.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000008b1', true);
do $$
declare
  v_target uuid := '00000000-0000-4000-8000-0000000008b4'::uuid;
  v_result record;
begin
  select * into v_result from public.set_user_role(v_target, 'owner');
  if not v_result.changed or v_result.new_role <> 'owner' then
    raise exception 'Owner could not create a non-final owner for guard verification';
  end if;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
do $$
declare
  v_owner uuid := (select value from phase_8b_ids where key = 'owner');
  v_target uuid := (select value from phase_8b_ids where key = 'target');
  v_cascade_target uuid := (select value from phase_8b_ids where key = 'cascade_target');
  v_final_owner_audit_count integer;
begin
  -- target is also an owner, so this privileged owner demotion and deletion
  -- are non-final and must succeed with exactly one audit event each.
  update public.user_roles set role = 'manager' where user_id = v_owner;
  if (select role from public.user_roles where user_id = v_owner) <> 'manager'::public.app_role
     or (select count(*) from public.audit_logs as audit_row
         where audit_row.entity_type = 'user_role'
           and audit_row.entity_id = v_owner
           and audit_row.action = 'update'
           and audit_row.old_values @> jsonb_build_object('role', 'owner')
           and audit_row.new_values @> jsonb_build_object('role', 'manager', 'origin', 'system')) <> 1 then
    raise exception 'Privileged non-final owner demotion was not audited exactly once';
  end if;
  update public.user_roles set role = 'owner' where user_id = v_owner;
  delete from public.user_roles where user_id = v_owner;
  if exists (select 1 from public.user_roles where user_id = v_owner) then
    raise exception 'Privileged deletion did not remove a non-final owner';
  end if;
  if (select count(*) from public.audit_logs as audit_row
      where audit_row.entity_type = 'user_role'
        and audit_row.entity_id = v_owner
        and audit_row.action = 'delete'
        and audit_row.old_values @> jsonb_build_object('target_user_id', v_owner, 'role', 'owner', 'origin', 'system')) <> 1 then
    raise exception 'Non-final owner removal did not create exactly one system audit row';
  end if;

  -- target is now the only owner in this database. Rejected writes must not
  -- alter it or reach the AFTER audit trigger.
  select count(*) into v_final_owner_audit_count
  from public.audit_logs as audit_row
  where audit_row.entity_type = 'user_role' and audit_row.entity_id = v_target;
  begin
    delete from public.user_roles where user_id = v_target;
    raise exception 'Privileged direct deletion removed the final owner';
  exception when check_violation then null;
  end;
  begin
    update public.user_roles set role = 'manager' where user_id = v_target;
    raise exception 'Privileged direct demotion changed the final owner';
  exception when check_violation then null;
  end;
  if not exists (
    select 1 from public.user_roles where user_id = v_target and role = 'owner'::public.app_role
  ) or (select count(*) from public.audit_logs as audit_row
        where audit_row.entity_type = 'user_role' and audit_row.entity_id = v_target) <> v_final_owner_audit_count then
    raise exception 'Final-owner guard changed authority or audited a rejected write';
  end if;

  -- target remains final, making this cascade target non-final. This exercises
  -- profile -> user_roles cascade and the single system audit event.
  insert into public.user_roles(user_id, role) values (v_cascade_target, 'owner');
  delete from public.profiles where id = v_cascade_target;
  if exists (select 1 from public.user_roles where user_id = v_cascade_target) then
    raise exception 'Profile deletion did not cascade role deletion';
  end if;
  if (select count(*) from public.audit_logs as audit_row
    where audit_row.entity_type = 'user_role'
      and audit_row.entity_id = v_cascade_target
      and audit_row.action = 'delete'
      and audit_row.actor_user_id is null
      and audit_row.old_values @> jsonb_build_object(
        'target_user_id', v_cascade_target,
        'role', 'owner',
        'origin', 'system'
      )
      and audit_row.old_values ? 'actor_user_id_snapshot'
      and audit_row.old_values->'actor_user_id_snapshot' = 'null'::jsonb
  ) <> 1 then raise exception 'Cascading role deletion was not recorded exactly once as a system authority event'; end if;
end;
$$;

reset role;
rollback;
