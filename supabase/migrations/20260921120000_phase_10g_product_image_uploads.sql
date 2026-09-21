-- Phase 10G: public product photography with manager/owner-only Storage writes.
-- Legacy root-relative Vite assets remain valid and are not migrated.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = true,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The restrictive policies ensure a broad policy introduced elsewhere cannot
-- accidentally grant product-image mutation to anonymous callers or staff.
create policy "product_images_no_anon_insert"
on storage.objects as restrictive for insert to anon
with check (bucket_id <> 'product-images');

create policy "product_images_no_anon_update"
on storage.objects as restrictive for update to anon
using (bucket_id <> 'product-images')
with check (bucket_id <> 'product-images');

create policy "product_images_no_anon_delete"
on storage.objects as restrictive for delete to anon
using (bucket_id <> 'product-images');

create policy "product_images_catalog_managers_insert_only"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'product-images'
  or public.is_manager_or_owner()
);

create policy "product_images_catalog_managers_update_only"
on storage.objects as restrictive for update to authenticated
using (
  bucket_id <> 'product-images'
  or public.is_manager_or_owner()
)
with check (
  bucket_id <> 'product-images'
  or public.is_manager_or_owner()
);

create policy "product_images_catalog_managers_delete_only"
on storage.objects as restrictive for delete to authenticated
using (
  bucket_id <> 'product-images'
  or public.is_manager_or_owner()
);

create policy "product_images_manager_owner_insert"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-images'
  and public.is_manager_or_owner()
);

create policy "product_images_manager_owner_update"
on storage.objects for update to authenticated
using (
  bucket_id = 'product-images'
  and public.is_manager_or_owner()
)
with check (
  bucket_id = 'product-images'
  and public.is_manager_or_owner()
);

create policy "product_images_manager_owner_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-images'
  and public.is_manager_or_owner()
);

alter table public.product_images
  add column storage_bucket text;

alter table public.product_images
  drop constraint product_images_root_relative_local_image_path;

alter table public.product_images
  add constraint product_images_storage_reference_valid check (
    (
      storage_bucket is null
      and storage_path ~* '^/[A-Za-z0-9][A-Za-z0-9._/-]*[.](jpg|jpeg|png|webp)$'
    )
    or (
      storage_bucket = 'product-images'
      and storage_path ~* (
        '^products/' || product_id::text || '/'
        || '[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
        || '[.](jpg|png|webp)$'
      )
    )
  );

create or replace function public.attach_admin_product_image(
  p_product_id uuid,
  p_storage_bucket text,
  p_storage_path text,
  p_alt_text text,
  p_display_order integer
)
returns public.product_images
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_has_images boolean;
  v_image public.product_images;
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Catalog management permission required' using errcode = '42501';
  end if;

  -- Serializes attachment RPCs for one product, so concurrent callers cannot
  -- both observe an empty image set and create competing primary images.
  perform 1
  from public.products
  where id = p_product_id
  for update;
  if not found then
    raise exception 'Product does not exist' using errcode = '23503';
  end if;

  select exists (
    select 1
    from public.product_images
    where product_id = p_product_id
  ) into v_has_images;

  insert into public.product_images (
    product_id, storage_bucket, storage_path, alt_text, display_order, is_primary
  ) values (
    p_product_id, p_storage_bucket, p_storage_path, p_alt_text, p_display_order,
    not v_has_images
  )
  returning * into v_image;

  return v_image;
end;
$$;

revoke all on function public.attach_admin_product_image(uuid, text, text, text, integer) from public;
revoke all on function public.attach_admin_product_image(uuid, text, text, text, integer) from anon;
revoke all on function public.attach_admin_product_image(uuid, text, text, text, integer) from service_role;
grant execute on function public.attach_admin_product_image(uuid, text, text, text, integer) to authenticated;

comment on column public.product_images.storage_bucket is
  'NULL identifies a legacy root-relative Vite asset; product-images identifies a stable public Storage object path.';
