-- Phase 1 RLS verification. Run in the Supabase SQL editor after:
-- 1. applying the migration;
-- 2. creating an owner and a non-owner Auth user; and
-- 3. replacing the UUIDs below with those Auth user IDs.
--
-- This runs as the authenticated database role to exercise RLS. It verifies that
-- security-definer has_role() works inside user_roles policies without recursion,
-- and that ordinary users cannot update protected profile columns.

begin;

set local role authenticated;

-- Owner: helper must resolve through user_roles without recursive RLS.
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
begin
  if not public.has_role('owner'::public.app_role) then
    raise exception 'Owner role helper test failed';
  end if;

  if not exists (select 1 from public.user_roles) then
    raise exception 'Owner user_roles policy test failed';
  end if;
end;
$$;

-- Non-owner: own membership is visible, but role management is denied.
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
begin
  if public.has_role('owner'::public.app_role) then
    raise exception 'Non-owner role helper test failed';
  end if;

  if not exists (
    select 1 from public.user_roles where user_id = auth.uid()
  ) then
    raise exception 'Own user_roles policy test failed';
  end if;

  begin
    insert into public.user_roles (user_id, role)
    values (auth.uid(), 'owner'::public.app_role);
    raise exception 'A non-owner unexpectedly granted a role';
  exception
    when insufficient_privilege then
      null;
  end;
end;
$$;

-- The column-level grant blocks direct protected-column updates. The profile trigger
-- is a second guard, including for any future columns not explicitly whitelisted.
do $$
begin
  begin
    update public.profiles
    set id = gen_random_uuid()
    where id = auth.uid();
    raise exception 'A non-owner unexpectedly updated profiles.id';
  exception
    when insufficient_privilege then
      null;
  end;

  update public.profiles
  set display_name = 'RLS verification user'
  where id = auth.uid();
end;
$$;

rollback;
