-- Phase 1: Supabase foundation and admin authentication/authorization.
-- This migration intentionally creates no customer, product, inventory, order, or payment objects.

create type public.app_role as enum ('owner', 'manager', 'staff');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  user_id uuid not null references public.profiles (id) on delete cascade,
  role public.app_role not null,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);

create index user_roles_role_user_id_idx on public.user_roles (role, user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- The whitelist protects current and future profile columns at the database layer.
-- UPDATE privileges below additionally limit authenticated callers to display_name.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if (to_jsonb(new) - array['display_name', 'updated_at'])
     is distinct from
     (to_jsonb(old) - array['display_name', 'updated_at']) then
    raise exception 'Only display_name may be updated on profiles'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger profiles_protect_columns_before_update
before update on public.profiles
for each row execute function public.protect_profile_columns();

create trigger profiles_set_updated_at_before_update
before update on public.profiles
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '')
  );
  return new;
end;
$$;

create trigger auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- SECURITY DEFINER is intentional: this function reads user_roles without invoking
-- caller RLS, so user_roles policies can safely call it without recursive RLS.
create or replace function public.has_role(required_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.user_roles as role_membership
    where role_membership.user_id = auth.uid()
      and role_membership.role = required_role
  );
$$;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.has_role('owner'::public.app_role);
$$;

create or replace function public.is_manager_or_owner()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.has_role('manager'::public.app_role)
      or public.has_role('owner'::public.app_role);
$$;

create or replace function public.is_staff_or_above()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select public.has_role('staff'::public.app_role)
      or public.is_manager_or_owner();
$$;

revoke all on function public.handle_new_auth_user() from public;
revoke all on function public.has_role(public.app_role) from public;
revoke all on function public.is_owner() from public;
revoke all on function public.is_manager_or_owner() from public;
revoke all on function public.is_staff_or_above() from public;
grant execute on function public.has_role(public.app_role) to authenticated;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.is_manager_or_owner() to authenticated;
grant execute on function public.is_staff_or_above() to authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;

revoke all on table public.profiles from anon, authenticated;
revoke all on table public.user_roles from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (display_name) on table public.profiles to authenticated;
grant select, insert, update, delete on table public.user_roles to authenticated;

create policy "profiles_select_own_or_owner"
on public.profiles
for select
to authenticated
using (id = auth.uid() or public.is_owner());

create policy "profiles_update_display_name_own_or_owner"
on public.profiles
for update
to authenticated
using (id = auth.uid() or public.is_owner())
with check (id = auth.uid() or public.is_owner());

create policy "user_roles_select_own_or_owner"
on public.user_roles
for select
to authenticated
using (user_id = auth.uid() or public.is_owner());

create policy "user_roles_owner_manage"
on public.user_roles
for all
to authenticated
using (public.is_owner())
with check (public.is_owner());

comment on function public.protect_profile_columns() is
  'Database whitelist: only display_name and trigger-managed updated_at may change.';
comment on function public.has_role(public.app_role) is
  'Security-definer helper intentionally bypassing user_roles RLS to prevent policy recursion.';
