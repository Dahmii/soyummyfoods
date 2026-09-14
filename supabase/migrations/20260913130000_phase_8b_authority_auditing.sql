-- Phase 8B: single-role authority management with durable role-transition audit.

do $$
begin
  if exists (
    select 1
    from public.user_roles as role_membership
    group by role_membership.user_id
    having count(*) > 1
  ) then
    raise exception 'Phase 8B cannot enforce one application role per user: existing users have multiple role rows'
      using errcode = '23514';
  end if;
end;
$$;

alter table public.user_roles
  add constraint user_roles_one_role_per_user unique (user_id);

alter table public.audit_logs drop constraint audit_logs_entity_type_check;
alter table public.audit_logs add constraint audit_logs_entity_type_check
  check (entity_type in (
    'category',
    'product',
    'product_image',
    'business_settings',
    'delivery_zone',
    'inventory',
    'order',
    'payment',
    'user_role'
  ));

create or replace function public.write_user_role_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_target_user_id uuid;
  v_previous_role text;
  v_next_role text;
  v_origin text := case when v_actor_id is null then 'system' else 'authenticated_admin' end;
begin
  if tg_op = 'INSERT' then
    v_target_user_id := new.user_id;
    v_next_role := new.role::text;
  elsif tg_op = 'DELETE' then
    v_target_user_id := old.user_id;
    v_previous_role := old.role::text;
  else
    v_target_user_id := new.user_id;
    v_previous_role := old.role::text;
    v_next_role := new.role::text;
  end if;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor_id,
    lower(tg_op),
    'user_role',
    v_target_user_id,
    jsonb_build_object(
      'target_user_id', v_target_user_id,
      'role', v_previous_role,
      'actor_user_id_snapshot', v_actor_id,
      'origin', v_origin
    ),
    jsonb_build_object(
      'target_user_id', v_target_user_id,
      'role', v_next_role,
      'actor_user_id_snapshot', v_actor_id,
      'origin', v_origin
    )
  );

  return coalesce(new, old);
end;
$$;

create trigger user_roles_write_audit_after_mutation
after insert or update or delete on public.user_roles
for each row execute function public.write_user_role_audit_log();

create or replace function public.prevent_final_owner_removal()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_owner_count integer;
begin
  if old.role <> 'owner'::public.app_role
     or (tg_op = 'UPDATE' and new.role = 'owner'::public.app_role) then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  -- This is the same authority lock used by set_user_role(), so privileged
  -- writes and profile/Auth cascades cannot bypass final-owner protection.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.set_user_role:authority')::bigint
  );

  select count(*) into v_owner_count
  from public.user_roles as role_membership
  where role_membership.role = 'owner'::public.app_role;
  if v_owner_count <= 1 then
    raise exception 'The final owner cannot be demoted or removed' using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger user_roles_prevent_final_owner_removal_before_mutation
before update or delete on public.user_roles
for each row execute function public.prevent_final_owner_removal();

create or replace function public.set_user_role(
  p_target_user_id uuid,
  p_next_role public.app_role default null
)
returns table (
  user_id uuid,
  previous_role public.app_role,
  new_role public.app_role,
  changed boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_target_profile_id uuid;
  v_current_role public.app_role;
  v_owner_count integer;
  v_transition_at timestamptz := now();
begin
  if v_actor_id is null then
    raise exception 'Role management permission required' using errcode = '42501';
  end if;
  if p_target_user_id is null then
    raise exception 'Role management target is required' using errcode = '22023';
  end if;
  if p_target_user_id = v_actor_id then
    raise exception 'Users cannot change their own role' using errcode = '42501';
  end if;
  if not public.is_owner() then
    raise exception 'Role management permission required' using errcode = '42501';
  end if;

  -- Serializes every trusted authority transition, including the final-owner
  -- count and its subsequent insert, update, or delete.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.set_user_role:authority')::bigint
  );

  if not public.is_owner() then
    raise exception 'Role management permission required' using errcode = '42501';
  end if;

  select profile_row.id into v_target_profile_id
  from public.profiles as profile_row
  where profile_row.id = p_target_user_id
  for key share;
  if not found then
    raise exception 'Role management target was not found' using errcode = '23503';
  end if;

  select role_membership.role into v_current_role
  from public.user_roles as role_membership
  where role_membership.user_id = p_target_user_id
  for update;

  if v_current_role is not distinct from p_next_role then
    return query select p_target_user_id, v_current_role, v_current_role, false;
    return;
  end if;

  if v_current_role = 'owner'::public.app_role
     and p_next_role is distinct from 'owner'::public.app_role then
    select count(*) into v_owner_count
    from public.user_roles as role_membership
    where role_membership.role = 'owner'::public.app_role;
    if v_owner_count <= 1 then
      raise exception 'The final owner cannot be demoted or removed' using errcode = '23514';
    end if;
  end if;

  if v_current_role is null then
    insert into public.user_roles (user_id, role, granted_by, granted_at)
    values (p_target_user_id, p_next_role, v_actor_id, v_transition_at);
  elsif p_next_role is null then
    delete from public.user_roles as role_membership
    where role_membership.user_id = p_target_user_id;
  else
    update public.user_roles as role_membership
    set role = p_next_role,
        granted_by = v_actor_id,
        granted_at = v_transition_at
    where role_membership.user_id = p_target_user_id;
  end if;

  return query select p_target_user_id, v_current_role, p_next_role, true;
end;
$$;

revoke insert, update, delete on table public.user_roles from public;
revoke insert, update, delete on table public.user_roles from anon;
revoke insert, update, delete on table public.user_roles from authenticated;
grant select on table public.user_roles to authenticated;

drop policy "user_roles_owner_manage" on public.user_roles;

revoke all on function public.write_user_role_audit_log() from public;
revoke all on function public.prevent_final_owner_removal() from public;
revoke all on function public.set_user_role(uuid, public.app_role) from public;
revoke all on function public.set_user_role(uuid, public.app_role) from anon;
revoke all on function public.set_user_role(uuid, public.app_role) from service_role;
grant execute on function public.set_user_role(uuid, public.app_role) to authenticated;

comment on function public.set_user_role(uuid, public.app_role) is
  'Owner-only, serialized application-role transition. NULL p_next_role removes application access.';
comment on function public.write_user_role_audit_log() is
  'Writes role transition evidence for trusted, privileged, and cascading role mutations.';
comment on function public.prevent_final_owner_removal() is
  'Shared-lock database invariant preventing any write path from removing the final owner.';
