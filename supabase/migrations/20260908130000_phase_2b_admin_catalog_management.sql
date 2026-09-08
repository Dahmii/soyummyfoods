-- Phase 2B: authoritative catalog administration, attribution, and audit history.

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.profiles (id) on delete set null,
  action text not null check (action in ('insert', 'update', 'delete')),
  entity_type text not null check (entity_type in ('category', 'product', 'product_image')),
  entity_id uuid not null,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_entity_created_at_idx
  on public.audit_logs (entity_type, entity_id, created_at desc);
create index audit_logs_actor_created_at_idx
  on public.audit_logs (actor_user_id, created_at desc);

alter table public.product_images
  add constraint product_images_root_relative_local_image_path check (
    storage_path ~* '^/[A-Za-z0-9][A-Za-z0-9._/-]*[.](jpg|jpeg|png|webp)$'
  );

create or replace function public.set_catalog_actor_and_lock_slug()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by = auth.uid();
    new.updated_by = auth.uid();
  else
    if new.slug is distinct from old.slug then
      raise exception 'Catalog slugs are immutable' using errcode = '42501';
    end if;
    new.created_by = old.created_by;
    new.updated_by = auth.uid();
  end if;
  return new;
end;
$$;

create trigger categories_set_actor_and_lock_slug_before_write
before insert or update on public.categories
for each row execute function public.set_catalog_actor_and_lock_slug();

create trigger products_set_actor_and_lock_slug_before_write
before insert or update on public.products
for each row execute function public.set_catalog_actor_and_lock_slug();

create or replace function public.ensure_active_product_has_primary_image()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  checked_product_id uuid := coalesce(
    (to_jsonb(new) ->> 'product_id')::uuid,
    (to_jsonb(old) ->> 'product_id')::uuid,
    (to_jsonb(new) ->> 'id')::uuid,
    (to_jsonb(old) ->> 'id')::uuid
  );
begin
  if exists (
    select 1 from public.products product
    where product.id = checked_product_id
      and product.status = 'active'::public.product_status
      and not exists (
        select 1 from public.product_images image
        where image.product_id = product.id and image.is_primary
      )
  ) then
    raise exception 'Active products must have a primary image' using errcode = '23514';
  end if;
  return null;
end;
$$;

create constraint trigger products_require_primary_image_when_active
after insert or update of status on public.products
deferrable initially deferred
for each row execute function public.ensure_active_product_has_primary_image();

create constraint trigger product_images_preserve_active_primary_image
after insert or update or delete on public.product_images
deferrable initially deferred
for each row execute function public.ensure_active_product_has_primary_image();

create or replace function public.set_product_primary_image(target_product_id uuid, target_image_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if not public.is_manager_or_owner() then
    raise exception 'Catalog management permission required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.product_images
    where id = target_image_id and product_id = target_product_id
  ) then
    raise exception 'Image does not belong to product' using errcode = '23503';
  end if;

  update public.product_images
  set is_primary = false
  where product_id = target_product_id and is_primary;

  update public.product_images
  set is_primary = true
  where id = target_image_id and product_id = target_product_id;
end;
$$;

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
  end;
begin
  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    auth.uid(), lower(tg_op), entity_name,
    coalesce(new.id, old.id),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;

create trigger categories_write_audit_after_mutation
after insert or update or delete on public.categories
for each row execute function public.write_catalog_audit_log();
create trigger products_write_audit_after_mutation
after insert or update or delete on public.products
for each row execute function public.write_catalog_audit_log();
create trigger product_images_write_audit_after_mutation
after insert or update or delete on public.product_images
for each row execute function public.write_catalog_audit_log();

alter table public.audit_logs enable row level security;
revoke all on table public.audit_logs from anon, authenticated;
grant select on table public.audit_logs to authenticated;
create policy "audit_logs_owner_read"
on public.audit_logs for select to authenticated
using (public.is_owner());

revoke all on function public.set_product_primary_image(uuid, uuid) from public;
grant execute on function public.set_product_primary_image(uuid, uuid) to authenticated;

drop policy "categories_manager_owner_manage" on public.categories;
drop policy "products_manager_owner_manage" on public.products;
drop policy "product_images_manager_owner_manage" on public.product_images;

create policy "categories_manager_owner_insert"
on public.categories for insert to authenticated
with check (public.is_manager_or_owner());
create policy "categories_manager_owner_update"
on public.categories for update to authenticated
using (public.is_manager_or_owner()) with check (public.is_manager_or_owner());
create policy "categories_manager_owner_read_all"
on public.categories for select to authenticated
using (public.is_manager_or_owner());

create policy "products_manager_owner_insert"
on public.products for insert to authenticated
with check (public.is_manager_or_owner());
create policy "products_manager_owner_update"
on public.products for update to authenticated
using (public.is_manager_or_owner()) with check (public.is_manager_or_owner());
create policy "products_manager_owner_read_all"
on public.products for select to authenticated
using (public.is_manager_or_owner());

create policy "product_images_manager_owner_insert"
on public.product_images for insert to authenticated
with check (public.is_manager_or_owner());
create policy "product_images_manager_owner_update"
on public.product_images for update to authenticated
using (public.is_manager_or_owner()) with check (public.is_manager_or_owner());
create policy "product_images_manager_owner_delete"
on public.product_images for delete to authenticated
using (public.is_manager_or_owner());
create policy "product_images_manager_owner_read_all"
on public.product_images for select to authenticated
using (public.is_manager_or_owner());
