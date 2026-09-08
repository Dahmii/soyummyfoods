-- Phase 3: business configuration and delivery-zone foundation.

create table public.business_settings (
  id smallint primary key default 1 check (id = 1),
  business_name text not null check (btrim(business_name) <> ''),
  legal_name text,
  email text,
  phone text,
  whatsapp_number text,
  address_line_1 text,
  address_line_2 text,
  city text,
  postcode text,
  country text,
  currency_code char(3) not null default 'GBP' check (currency_code = 'GBP'),
  tax_enabled boolean not null default false,
  tax_label text,
  tax_rate_percent numeric(5,2),
  tax_registration_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  constraint business_settings_tax_rate_range check (
    tax_rate_percent is null or (tax_rate_percent >= 0 and tax_rate_percent <= 100)
  ),
  constraint business_settings_tax_configuration check (
    (not tax_enabled and tax_label is null and tax_rate_percent is null and tax_registration_number is null)
    or (tax_enabled and nullif(btrim(tax_label), '') is not null and tax_rate_percent is not null)
  )
);

create table public.delivery_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  is_active boolean not null default true,
  postcode_prefixes text[] not null check (cardinality(postcode_prefixes) > 0),
  delivery_fee numeric(10,2) not null check (delivery_fee >= 0),
  minimum_order numeric(10,2) check (minimum_order is null or minimum_order >= 0),
  match_priority integer not null default 0 check (match_priority >= 0),
  display_order integer not null default 0 check (display_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create index delivery_zones_active_priority_idx
  on public.delivery_zones (is_active, match_priority, id);

create or replace function public.normalize_postcode(value text)
returns text
language sql
immutable
strict
set search_path = pg_catalog, public
as $$
  select nullif(regexp_replace(upper(btrim(value)), '[[:space:]]+', '', 'g'), '');
$$;

create or replace function public.set_business_settings_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by = auth.uid();
    new.updated_by = auth.uid();
  else
    new.created_by = old.created_by;
    new.updated_by = auth.uid();
  end if;
  return new;
end;
$$;

create or replace function public.normalize_delivery_zone_and_set_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.postcode_prefixes is null or cardinality(new.postcode_prefixes) = 0 then
    raise exception 'Delivery zones require at least one postcode prefix' using errcode = '23514';
  end if;

  if exists (
    select 1
    from unnest(new.postcode_prefixes) as input_prefix
    where public.normalize_postcode(input_prefix) is null
       or public.normalize_postcode(input_prefix) !~ '^[A-Z0-9]+$'
  ) then
    raise exception 'Postcode prefixes must contain only letters and numbers' using errcode = '23514';
  end if;

  select array_agg(public.normalize_postcode(input_prefix) order by ordinal_position)
  into new.postcode_prefixes
  from unnest(new.postcode_prefixes) with ordinality as prefixes(input_prefix, ordinal_position);

  if exists (
    select 1
    from unnest(new.postcode_prefixes) as normalized_prefix
    group by normalized_prefix
    having count(*) > 1
  ) then
    raise exception 'A delivery zone cannot contain duplicate postcode prefixes' using errcode = '23514';
  end if;

  if new.is_active then
    -- Serialize checks for each prefix so concurrent writes cannot create an exact
    -- active-prefix conflict after both transactions initially see no conflict.
    perform pg_advisory_xact_lock(hashtext(normalized_prefix))
    from (
      select unnest(new.postcode_prefixes) as normalized_prefix
      order by normalized_prefix
    ) as prefix_locks;

    if exists (
      select 1
      from public.delivery_zones as existing_zone
      cross join unnest(existing_zone.postcode_prefixes) as existing_prefix(value)
      cross join unnest(new.postcode_prefixes) as proposed_prefix(value)
      where existing_zone.is_active
        and existing_zone.id is distinct from new.id
        and proposed_prefix.value = existing_prefix.value
    ) then
      raise exception 'Active delivery zones cannot share an exact postcode prefix' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.created_by = auth.uid();
    new.updated_by = auth.uid();
  else
    new.created_by = old.created_by;
    new.updated_by = auth.uid();
  end if;
  return new;
end;
$$;

create trigger business_settings_set_actor_before_write
before insert or update on public.business_settings
for each row execute function public.set_business_settings_actor();

create trigger business_settings_set_updated_at_before_update
before update on public.business_settings
for each row execute function public.set_updated_at();

create trigger delivery_zones_normalize_and_set_actor_before_write
before insert or update on public.delivery_zones
for each row execute function public.normalize_delivery_zone_and_set_actor();

create trigger delivery_zones_set_updated_at_before_update
before update on public.delivery_zones
for each row execute function public.set_updated_at();

alter table public.audit_logs drop constraint audit_logs_entity_type_check;
alter table public.audit_logs add constraint audit_logs_entity_type_check
  check (entity_type in ('category', 'product', 'product_image', 'business_settings', 'delivery_zone'));

create or replace function public.write_catalog_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  entity_name text := case tg_table_name
    when 'categories' then 'category'
    when 'products' then 'product'
    when 'product_images' then 'product_image'
    when 'business_settings' then 'business_settings'
    when 'delivery_zones' then 'delivery_zone'
  end;
  old_audit_values jsonb;
  new_audit_values jsonb;
  audit_entity_id uuid;
begin
  old_audit_values := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  new_audit_values := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;

  if tg_table_name = 'business_settings' then
    old_audit_values := old_audit_values - 'tax_registration_number';
    new_audit_values := new_audit_values - 'tax_registration_number';
    -- audit_logs.entity_id is UUID while the singleton has the fixed smallint ID 1.
    audit_entity_id := '00000000-0000-0000-0000-000000000001'::uuid;
  else
    audit_entity_id := coalesce(new.id, old.id);
  end if;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    auth.uid(), lower(tg_op), entity_name,
    audit_entity_id, old_audit_values, new_audit_values
  );
  return coalesce(new, old);
end;
$$;

create trigger business_settings_write_audit_after_mutation
after insert or update on public.business_settings
for each row execute function public.write_catalog_audit_log();

create trigger delivery_zones_write_audit_after_mutation
after insert or update on public.delivery_zones
for each row execute function public.write_catalog_audit_log();

create or replace function public.resolve_active_delivery_zone(postcode text)
returns table (
  zone_id uuid,
  zone_name text,
  delivery_fee numeric(10,2),
  minimum_order numeric(10,2),
  normalized_postcode text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with normalized as (
    select public.normalize_postcode(postcode) as value
  ), matches as (
    select
      zone.id,
      zone.name,
      zone.delivery_fee,
      zone.minimum_order,
      normalized.value as normalized_postcode,
      prefix.value as matched_prefix,
      zone.match_priority
    from normalized
    join public.delivery_zones as zone on zone.is_active
    cross join lateral unnest(zone.postcode_prefixes) as prefix(value)
    where normalized.value like prefix.value || '%'
  )
  select id, name, delivery_fee, minimum_order, normalized_postcode
  from matches
  order by length(matched_prefix) desc, match_priority asc, id asc
  limit 1;
$$;

revoke all on function public.normalize_postcode(text) from public, anon, authenticated;
revoke all on function public.resolve_active_delivery_zone(text) from public, anon, authenticated;

alter table public.business_settings enable row level security;
alter table public.delivery_zones enable row level security;

revoke all on table public.business_settings from anon, authenticated;
revoke all on table public.delivery_zones from anon, authenticated;

grant select, update on table public.business_settings to authenticated;
grant select, insert, update on table public.delivery_zones to authenticated;

create policy "business_settings_staff_read"
on public.business_settings for select to authenticated
using (public.is_staff_or_above());
create policy "business_settings_manager_owner_update"
on public.business_settings for update to authenticated
using (public.is_manager_or_owner()) with check (public.is_manager_or_owner());

create policy "delivery_zones_staff_read"
on public.delivery_zones for select to authenticated
using (public.is_staff_or_above());
create policy "delivery_zones_manager_owner_insert"
on public.delivery_zones for insert to authenticated
with check (public.is_manager_or_owner());
create policy "delivery_zones_manager_owner_update"
on public.delivery_zones for update to authenticated
using (public.is_manager_or_owner()) with check (public.is_manager_or_owner());

insert into public.business_settings (id, business_name, currency_code, tax_enabled)
values (1, 'So Yummy Foods', 'GBP', false);
