-- Phase 10G product-image Storage verification. Run after Phases 1-10G in a
-- disposable database only. Replace the three Auth UUID placeholders with
-- existing owner, manager, and staff users. All fixture rows are rolled back.

begin;

do $$
declare
  v_product_id_attnum smallint;
  v_storage_bucket_attnum smallint;
  v_attachment_definition text;
begin
  select attnum into v_product_id_attnum
  from pg_attribute
  where attrelid = 'public.product_images'::regclass
    and attname = 'product_id'
    and not attisdropped;
  select attnum into v_storage_bucket_attnum
  from pg_attribute
  where attrelid = 'public.product_images'::regclass
    and attname = 'storage_bucket'
    and not attisdropped;

  if not exists (
    select 1 from storage.buckets
    where id = 'product-images'
      and public = true
      and file_size_limit = 5242880
      and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']::text[]
  ) then raise exception 'product-images bucket configuration is incorrect'; end if;

  if v_storage_bucket_attnum is null then
    raise exception 'product_images.storage_bucket is missing';
  end if;
  if has_function_privilege('anon', 'public.attach_admin_product_image(uuid,text,text,text,integer)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.attach_admin_product_image(uuid,text,text,text,integer)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.attach_admin_product_image(uuid,text,text,text,integer)', 'EXECUTE') then
    raise exception 'Product-image attachment RPC grants are incorrect';
  end if;
  if not exists (
    select 1 from pg_index as index_row
    where index_row.indrelid = 'public.product_images'::regclass
      and index_row.indisunique
      and index_row.indpred is not null
      and index_row.indkey::smallint[] = array[v_product_id_attnum]
  ) then raise exception 'Primary-image uniqueness is missing'; end if;

  if (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and policyname in (
          'product_images_no_anon_insert',
          'product_images_no_anon_update',
          'product_images_no_anon_delete',
          'product_images_catalog_managers_insert_only',
          'product_images_catalog_managers_update_only',
          'product_images_catalog_managers_delete_only'
        )
        and permissive = 'RESTRICTIVE') <> 6
     or (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and policyname in (
          'product_images_manager_owner_insert',
          'product_images_manager_owner_update',
          'product_images_manager_owner_delete'
        )
        and permissive = 'PERMISSIVE') <> 3 then
    raise exception 'Product-image Storage mutation policies are missing';
  end if;
  select pg_get_functiondef('public.attach_admin_product_image(uuid,text,text,text,integer)'::regprocedure)
    into v_attachment_definition;
  if position('for update' in lower(v_attachment_definition)) = 0
     or position('not v_has_images' in lower(v_attachment_definition)) = 0
     or position('not public.is_manager_or_owner()' in lower(v_attachment_definition)) = 0 then
    raise exception 'Product-image attachment serialization is incorrect';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare
  v_category_id uuid := '00000000-0000-4000-8000-00000000010a'::uuid;
  v_legacy_product_id uuid := '00000000-0000-4000-8000-00000000010b'::uuid;
  v_mixed_product_id uuid := '00000000-0000-4000-8000-00000000010c'::uuid;
  v_storage_object_id uuid := '00000000-0000-4000-8000-00000000010d'::uuid;
  v_attachment_product_id uuid := '00000000-0000-4000-8000-00000000010f'::uuid;
  v_legacy_image_id uuid;
  v_storage_image_id uuid;
  v_secondary_image_id uuid;
  v_first_attachment public.product_images;
  v_second_attachment public.product_images;
begin
  insert into public.categories (id, name, slug, display_order)
  values (v_category_id, 'Phase 10G category', 'phase-10g-category', 99999);
  insert into public.products (
    id, category_id, slug, name, description, base_price,
    prep_time_minutes, status, display_order
  ) values
    (v_legacy_product_id, v_category_id, 'phase-10g-legacy', 'Phase 10G legacy', 'Disposable product.', 1, 1, 'draft', 99999),
    (v_mixed_product_id, v_category_id, 'phase-10g-mixed', 'Phase 10G mixed', 'Disposable product.', 1, 1, 'draft', 99998),
    (v_attachment_product_id, v_category_id, 'phase-10g-attach', 'Phase 10G attachment', 'Disposable product.', 1, 1, 'draft', 99997);

  select * into v_first_attachment
  from public.attach_admin_product_image(
    v_attachment_product_id,
    'product-images',
    'products/' || v_attachment_product_id::text || '/' || v_storage_object_id::text || '.jpg',
    'First attachment',
    0
  );
  select * into v_second_attachment
  from public.attach_admin_product_image(
    v_attachment_product_id,
    'product-images',
    'products/' || v_attachment_product_id::text || '/' || gen_random_uuid()::text || '.png',
    'Second attachment',
    1
  );
  if not v_first_attachment.is_primary
     or v_second_attachment.is_primary
     or (select count(*) from public.product_images where product_id = v_attachment_product_id and is_primary) <> 1 then
    raise exception 'Attachment RPC did not assign exactly one first primary image';
  end if;

  insert into public.product_images (product_id, storage_path, storage_bucket, is_primary, display_order)
  values (v_legacy_product_id, '/phase-10g-legacy.jpg', null, true, 0)
  returning id into v_legacy_image_id;
  insert into public.product_images (product_id, storage_path, storage_bucket, is_primary, display_order)
  values (
    v_mixed_product_id,
    'products/' || v_mixed_product_id::text || '/' || v_storage_object_id::text || '.jpg',
    'product-images', true, 0
  ) returning id into v_storage_image_id;
  insert into public.product_images (product_id, storage_path, storage_bucket, is_primary, display_order)
  values (v_mixed_product_id, '/phase-10g-secondary.webp', null, false, 1);
  select id into v_secondary_image_id
  from public.product_images
  where product_id = v_mixed_product_id and storage_path = '/phase-10g-secondary.webp';

  if not exists (select 1 from public.product_images where id = v_legacy_image_id and storage_bucket is null)
     or not exists (select 1 from public.product_images where id = v_storage_image_id and storage_bucket = 'product-images')
     or (select count(*) from public.product_images where product_id = v_mixed_product_id) <> 2 then
    raise exception 'Legacy or mixed image metadata is invalid';
  end if;

  begin
    insert into public.product_images (product_id, storage_path, storage_bucket)
    values (v_mixed_product_id, 'https://example.test/image.jpg', null);
    raise exception 'External image URL was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.product_images (product_id, storage_path, storage_bucket)
    values (v_mixed_product_id, 'products/not-a-product/not-a-uuid.jpg', 'product-images');
    raise exception 'Malformed Storage path was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.product_images (product_id, storage_path, storage_bucket)
    values (v_mixed_product_id, '/phase-10g.jpg', 'other-bucket');
    raise exception 'Unsupported Storage bucket was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.product_images (product_id, storage_path, storage_bucket, is_primary)
    values (
      v_mixed_product_id,
      'products/' || v_mixed_product_id::text || '/' || gen_random_uuid()::text || '.webp',
      'product-images', true
    );
    raise exception 'A second primary image was accepted';
  exception when unique_violation then null;
  end;

  perform public.set_product_primary_image(v_mixed_product_id, v_secondary_image_id);
  if (select count(*) from public.product_images where product_id = v_mixed_product_id and is_primary) <> 1
     or not exists (select 1 from public.product_images where id = v_secondary_image_id and is_primary) then
    raise exception 'Legacy image could not become primary in a mixed image set';
  end if;
  perform public.set_product_primary_image(v_mixed_product_id, v_storage_image_id);
  if (select count(*) from public.product_images where product_id = v_mixed_product_id and is_primary) <> 1
     or not exists (select 1 from public.product_images where id = v_storage_image_id and is_primary) then
    raise exception 'Storage-backed image could not become primary in a mixed image set';
  end if;

  update public.products set status = 'active' where id = v_mixed_product_id;
  set constraints products_require_primary_image_when_active immediate;
  begin
    delete from public.product_images where id = v_storage_image_id;
    set constraints product_images_preserve_active_primary_image immediate;
    raise exception 'Active product lost its only primary image';
  exception when check_violation then null;
  end;

  insert into storage.objects (id, bucket_id, name, owner_id)
  values (
    gen_random_uuid(),
    'product-images',
    'products/' || v_mixed_product_id::text || '/' || v_storage_object_id::text || '.jpg',
    auth.uid()
  );
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare
  v_mixed_product_id uuid := '00000000-0000-4000-8000-00000000010c'::uuid;
  v_object_id uuid := '00000000-0000-4000-8000-00000000010e'::uuid;
  v_attachment_product_id uuid := '00000000-0000-4000-8000-00000000010f'::uuid;
  v_attached public.product_images;
begin
  select * into v_attached
  from public.attach_admin_product_image(
    v_attachment_product_id,
    'product-images',
    'products/' || v_attachment_product_id::text || '/' || gen_random_uuid()::text || '.webp',
    'Manager attachment',
    2
  );
  if v_attached.is_primary then
    raise exception 'Manager attachment unexpectedly replaced the existing primary image';
  end if;
  insert into storage.objects (id, bucket_id, name, owner_id)
  values (
    gen_random_uuid(),
    'product-images',
    'products/' || v_mixed_product_id::text || '/' || v_object_id::text || '.png',
    auth.uid()
  );
  update storage.objects
  set metadata = jsonb_build_object('phase', '10g')
  where bucket_id = 'product-images'
    and name = 'products/' || v_mixed_product_id::text || '/' || v_object_id::text || '.png';
  delete from storage.objects
  where bucket_id = 'product-images'
    and name = 'products/' || v_mixed_product_id::text || '/' || v_object_id::text || '.png';
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare
  v_mixed_product_id uuid := '00000000-0000-4000-8000-00000000010c'::uuid;
begin
  begin
    perform public.attach_admin_product_image(
      v_mixed_product_id,
      'product-images',
      'products/' || v_mixed_product_id::text || '/' || gen_random_uuid()::text || '.webp',
      null,
      2
    );
    raise exception 'Staff attached product image metadata';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects (id, bucket_id, name, owner_id)
    values (gen_random_uuid(), 'product-images', 'products/' || v_mixed_product_id::text || '/' || gen_random_uuid()::text || '.webp', auth.uid());
    raise exception 'Staff inserted a product-image object';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
  begin
    perform public.attach_admin_product_image(
      '00000000-0000-4000-8000-00000000010c',
      'product-images',
      'products/00000000-0000-4000-8000-00000000010c/' || gen_random_uuid()::text || '.jpg',
      null,
      0
    );
    raise exception 'Anon attached product image metadata';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects (id, bucket_id, name)
    values (gen_random_uuid(), 'product-images', 'products/00000000-0000-4000-8000-00000000010c/00000000-0000-4000-8000-00000000010c.jpg');
    raise exception 'Anon inserted a product-image object';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
