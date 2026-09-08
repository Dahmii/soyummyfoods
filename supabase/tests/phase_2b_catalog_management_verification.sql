-- Phase 2B catalog-management verification. Run in the Supabase SQL editor only
-- after applying Phases 1, 2A, and 2B and replacing all three Auth UUID placeholders.
-- The three users must have owner, manager, and staff roles respectively. This script
-- uses browser-equivalent anon/authenticated roles and rolls every test row back.

begin;

create temporary table phase_2b_test_ids (
  key text primary key,
  value uuid not null
) on commit drop;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);

-- Owner mutations, authoritative attribution, immutable slugs, valid path acceptance,
-- audit creation/content, and active-product primary-image rules.
do $$
declare
  owner_category_id uuid;
  empty_product_id uuid;
  active_product_id uuid;
  active_primary_id uuid;
  active_secondary_id uuid;
  archived_product_id uuid;
  archived_primary_id uuid;
begin
  if not public.is_owner() then
    raise exception 'Owner role helper failed';
  end if;

  insert into public.categories (name, slug, display_order, created_by, updated_by)
  values (
    'Phase 2B owner category', 'phase-2b-owner-category', 900,
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000000'
  ) returning id into owner_category_id;
  insert into phase_2b_test_ids values ('owner_category', owner_category_id);

  if not exists (
    select 1 from public.categories
    where id = owner_category_id and created_by = auth.uid() and updated_by = auth.uid()
  ) then raise exception 'INSERT attribution was forgeable'; end if;

  update public.categories
  set name = 'Phase 2B owner category updated',
      created_by = '00000000-0000-0000-0000-000000000000',
      updated_by = '00000000-0000-0000-0000-000000000000'
  where id = owner_category_id;
  if not exists (
    select 1 from public.categories
    where id = owner_category_id and created_by = auth.uid() and updated_by = auth.uid()
  ) then raise exception 'UPDATE attribution was forgeable'; end if;

  begin
    update public.categories set slug = 'phase-2b-owner-category-mutated' where id = owner_category_id;
    raise exception 'Mutable category slug accepted';
  exception when insufficient_privilege then null;
  end;

  insert into public.products (
    category_id, slug, name, description, base_price, prep_time_minutes, status, display_order
  ) values (
    owner_category_id, 'phase-2b-empty-draft', 'Phase 2B empty draft',
    'Temporary verification product.', 1, 1, 'draft', 900
  ) returning id into empty_product_id;
  insert into phase_2b_test_ids values ('empty_draft_product', empty_product_id);
  begin
    update public.products set status = 'active' where id = empty_product_id;
    set constraints products_require_primary_image_when_active immediate;
    raise exception 'Product without a primary image became active';
  exception when check_violation then null;
  end;

  insert into public.products (
    category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order
  ) values (
    owner_category_id, 'phase-2b-active-unavailable', 'Phase 2B active unavailable',
    'Temporary verification product.', 1, 1, 'draft', false, 901
  ) returning id into active_product_id;
  insert into phase_2b_test_ids values ('active_unavailable_product', active_product_id);
  begin
    update public.products set slug = 'phase-2b-active-unavailable-mutated' where id = active_product_id;
    raise exception 'Mutable product slug accepted';
  exception when insufficient_privilege then null;
  end;

  insert into public.product_images (product_id, storage_path, is_primary)
  values (active_product_id, '/phase-2b-primary.JPG', true)
  returning id into active_primary_id;
  insert into phase_2b_test_ids values ('active_primary_image', active_primary_id);
  begin
    insert into public.product_images (product_id, storage_path)
    values (active_product_id, 'https://example.test/image.jpg');
    raise exception 'External image URL accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.product_images (product_id, storage_path)
    values (active_product_id, '/phase-2b-not-an-image.txt');
    raise exception 'Non-image path accepted';
  exception when check_violation then null;
  end;

  update public.products set status = 'active' where id = active_product_id;
  set constraints products_require_primary_image_when_active immediate;
  insert into public.product_images (product_id, storage_path, is_primary)
  values (active_product_id, '/phase-2b-secondary.png', false)
  returning id into active_secondary_id;
  delete from public.product_images where id = active_secondary_id;
  if exists (select 1 from public.product_images where id = active_secondary_id) then
    raise exception 'Non-primary image delete failed';
  end if;
  begin
    delete from public.product_images where id = active_primary_id;
    set constraints product_images_preserve_active_primary_image immediate;
    raise exception 'Active product lost its sole primary image';
  exception when check_violation then null;
  end;

  insert into public.products (
    category_id, slug, name, description, base_price, prep_time_minutes, status, display_order
  ) values (
    owner_category_id, 'phase-2b-archive-restore', 'Phase 2B archive restore',
    'Temporary verification product.', 1, 1, 'draft', 902
  ) returning id into archived_product_id;
  insert into public.product_images (product_id, storage_path, is_primary)
  values (archived_product_id, '/phase-2b-archive-primary.webp', true)
  returning id into archived_primary_id;
  update public.products set status = 'active' where id = archived_product_id;
  set constraints products_require_primary_image_when_active immediate;
  update public.products set status = 'archived' where id = archived_product_id;
  delete from public.product_images where id = archived_primary_id;
  begin
    update public.products set status = 'active' where id = archived_product_id;
    set constraints products_require_primary_image_when_active immediate;
    raise exception 'Archived product without primary image was restored';
  exception when check_violation then null;
  end;
  insert into public.product_images (product_id, storage_path, is_primary)
  values (archived_product_id, '/phase-2b-restored-primary.webp', true);
  update public.products set status = 'active' where id = archived_product_id;
  set constraints products_require_primary_image_when_active immediate;
  insert into phase_2b_test_ids values ('archived_product', archived_product_id);
  update public.products set status = 'archived' where id = archived_product_id;

  if not exists (
    select 1 from public.audit_logs
    where entity_type = 'category' and entity_id = owner_category_id and action = 'insert'
      and actor_user_id = auth.uid() and old_values is null and new_values is not null
  ) or not exists (
    select 1 from public.audit_logs
    where entity_type = 'category' and entity_id = owner_category_id and action = 'update'
      and actor_user_id = auth.uid() and old_values is not null and new_values is not null
  ) or not exists (
    select 1 from public.audit_logs
    where entity_type = 'product_image' and entity_id = active_primary_id and action = 'insert'
      and actor_user_id = auth.uid() and old_values is null and new_values is not null
  ) then raise exception 'Category audit INSERT/UPDATE content missing'; end if;
end;
$$;

-- Owner primary switching is atomic; audit rows remain database-managed only.
do $$
declare
  target_product_id uuid := (select value from phase_2b_test_ids where key = 'active_unavailable_product');
  old_primary_id uuid := (select value from phase_2b_test_ids where key = 'active_primary_image');
  replacement_id uuid;
begin
  insert into public.product_images (product_id, storage_path, is_primary)
  values (target_product_id, '/phase-2b-owner-replacement.jpeg', false)
  returning id into replacement_id;
  insert into phase_2b_test_ids values ('owner_replacement_image', replacement_id);
  perform public.set_product_primary_image(target_product_id, replacement_id);
  if (select count(*) from public.product_images where product_id = target_product_id and is_primary) <> 1
     or not exists (select 1 from public.product_images where id = replacement_id and is_primary) then
    raise exception 'Owner primary-image switch was not atomic';
  end if;
  delete from public.product_images where id = old_primary_id;
  if not exists (
    select 1 from public.audit_logs
    where entity_type = 'product_image' and entity_id = old_primary_id and action = 'delete'
      and actor_user_id = auth.uid() and old_values is not null and new_values is null
  ) then raise exception 'Product-image DELETE audit content missing'; end if;
  begin insert into public.audit_logs (actor_user_id, action, entity_type, entity_id) values (auth.uid(), 'insert', 'category', gen_random_uuid()); raise exception 'Owner directly inserted audit row'; exception when insufficient_privilege then null; end;
  begin update public.audit_logs set action = 'delete' where entity_id = target_product_id; raise exception 'Owner directly updated audit row'; exception when insufficient_privilege then null; end;
  begin delete from public.audit_logs where entity_id = target_product_id; raise exception 'Owner directly deleted audit row'; exception when insufficient_privilege then null; end;
end;
$$;

-- Manager CRUD and RPC access, without category/product deletion or audit access.
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
declare
  category_id uuid; manager_product_id uuid; primary_id uuid; secondary_id uuid;
  other_product_id uuid; other_image_id uuid;
begin
  if not public.is_manager_or_owner() or public.is_owner() then raise exception 'Manager role helper failed'; end if;
  insert into public.categories (name, slug, display_order)
  values ('Phase 2B manager category', 'phase-2b-manager-category', 910) returning id into category_id;
  update public.categories set name = 'Phase 2B manager category updated' where id = category_id;
  insert into phase_2b_test_ids values ('manager_category', category_id);
  insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order)
  values (category_id, 'phase-2b-manager-product', 'Phase 2B manager product', 'Temporary verification product.', 2, 1, 'draft', 910) returning id into manager_product_id;
  update public.products set name = 'Phase 2B manager product updated' where id = manager_product_id;
  insert into phase_2b_test_ids values ('manager_product', manager_product_id);
  insert into public.product_images (product_id, storage_path, is_primary)
  values (manager_product_id, '/phase-2b-manager-primary.jpg', true) returning id into primary_id;
  insert into public.product_images (product_id, storage_path, is_primary)
  values (manager_product_id, '/phase-2b-manager-secondary.jpg', false) returning id into secondary_id;
  update public.product_images set alt_text = 'Updated by manager' where id = secondary_id;
  perform public.set_product_primary_image(manager_product_id, secondary_id);
  if (select count(*) from public.product_images where product_id = manager_product_id and is_primary) <> 1
     or not exists (select 1 from public.product_images where id = secondary_id and is_primary) then
    raise exception 'Manager primary-image switch failed';
  end if;
  delete from public.product_images where id = primary_id;
  if exists (select 1 from public.product_images where id = primary_id) then raise exception 'Manager could not delete non-primary image metadata'; end if;
  insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order)
  values (category_id, 'phase-2b-manager-other-product', 'Phase 2B manager other product', 'Temporary verification product.', 2, 1, 'draft', 911) returning id into other_product_id;
  insert into public.product_images (product_id, storage_path, is_primary)
  values (other_product_id, '/phase-2b-manager-other.jpg', true) returning id into other_image_id;
  begin perform public.set_product_primary_image(manager_product_id, other_image_id); raise exception 'Manager assigned Product B image to Product A'; exception when foreign_key_violation then null; end;
  delete from public.categories where id = category_id;
  if found then raise exception 'Manager deleted category'; end if;
  delete from public.products where id = manager_product_id;
  if found then raise exception 'Manager deleted product'; end if;
  if exists (select 1 from public.audit_logs) then raise exception 'Manager read audit logs'; end if;
  begin insert into public.audit_logs (actor_user_id, action, entity_type, entity_id) values (auth.uid(), 'insert', 'category', gen_random_uuid()); raise exception 'Manager directly inserted audit row'; exception when insufficient_privilege then null; end;
  begin update public.audit_logs set action = 'delete'; raise exception 'Manager directly updated audit rows'; exception when insufficient_privilege then null; end;
  begin delete from public.audit_logs; raise exception 'Manager directly deleted audit rows'; exception when insufficient_privilege then null; end;
end;
$$;

-- Staff sees active records only, including unavailable ones, but cannot mutate.
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
declare
  active_product_id uuid := (select value from phase_2b_test_ids where key = 'active_unavailable_product');
  draft_product_id uuid := (select value from phase_2b_test_ids where key = 'empty_draft_product');
  archived_product_id uuid := (select value from phase_2b_test_ids where key = 'archived_product');
  manager_product_id uuid := (select value from phase_2b_test_ids where key = 'manager_product');
  active_image_id uuid := (select value from phase_2b_test_ids where key = 'owner_replacement_image');
begin
  if exists (select 1 from public.products where id = draft_product_id)
     or exists (select 1 from public.products where id = manager_product_id)
     or exists (select 1 from public.products where id = archived_product_id) then raise exception 'Staff read draft or archived catalog data'; end if;
  if not exists (select 1 from public.products where id = active_product_id and not is_available) then raise exception 'Staff could not read active unavailable product'; end if;
  begin insert into public.categories (name, slug, display_order) values ('Staff write', 'phase-2b-staff-write', 999); raise exception 'Staff wrote category'; exception when insufficient_privilege then null; end;
  begin insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order) values ((select value from phase_2b_test_ids where key = 'owner_category'), 'phase-2b-staff-product', 'Staff write', 'Temporary.', 1, 1, 'draft', 999); raise exception 'Staff wrote product'; exception when insufficient_privilege then null; end;
  begin insert into public.product_images (product_id, storage_path) values (active_product_id, '/phase-2b-staff-image.jpg'); raise exception 'Staff wrote image metadata'; exception when insufficient_privilege then null; end;
  update public.products set base_price = 99 where id = active_product_id;
  if found then raise exception 'Staff updated product'; end if;
  delete from public.product_images where id = active_image_id;
  if found then raise exception 'Staff deleted image metadata'; end if;
  begin perform public.set_product_primary_image(active_product_id, active_image_id); raise exception 'Staff called primary-image RPC'; exception when insufficient_privilege then null; end;
  if exists (select 1 from public.audit_logs) then raise exception 'Staff read audit logs'; end if;
  begin insert into public.audit_logs (action, entity_type, entity_id) values ('insert', 'category', gen_random_uuid()); raise exception 'Staff inserted audit row'; exception when insufficient_privilege then null; end;
  begin update public.audit_logs set action = 'delete'; raise exception 'Staff updated audit row'; exception when insufficient_privilege then null; end;
  begin delete from public.audit_logs; raise exception 'Staff deleted audit row'; exception when insufficient_privilege then null; end;
end;
$$;

-- Anon has public reads only: active/unavailable readable, draft hidden, no writes/audit.
set local role anon;
do $$
declare
  active_product_id uuid := (select value from phase_2b_test_ids where key = 'active_unavailable_product');
  draft_product_id uuid := (select value from phase_2b_test_ids where key = 'empty_draft_product');
  archived_product_id uuid := (select value from phase_2b_test_ids where key = 'archived_product');
begin
  if not exists (select 1 from public.products where id = active_product_id and not is_available) then raise exception 'Anon could not read active unavailable product'; end if;
  if exists (select 1 from public.products where id = draft_product_id)
     or exists (select 1 from public.products where id = archived_product_id) then raise exception 'Anon read draft or archived product'; end if;
  begin insert into public.categories (name, slug, display_order) values ('Anon write', 'phase-2b-anon-write', 999); raise exception 'Anon wrote category'; exception when insufficient_privilege then null; end;
  begin insert into public.products (category_id, slug, name, description, base_price, prep_time_minutes, status, display_order) values ((select value from phase_2b_test_ids where key = 'owner_category'), 'phase-2b-anon-product', 'Anon write', 'Temporary.', 1, 1, 'draft', 999); raise exception 'Anon wrote product'; exception when insufficient_privilege then null; end;
  begin insert into public.product_images (product_id, storage_path) values (active_product_id, '/phase-2b-anon-image.jpg'); raise exception 'Anon wrote image metadata'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.audit_logs; raise exception 'Anon read audit logs'; exception when insufficient_privilege then null; end;
  begin insert into public.audit_logs (action, entity_type, entity_id) values ('insert', 'category', gen_random_uuid()); raise exception 'Anon inserted audit row'; exception when insufficient_privilege then null; end;
  begin update public.audit_logs set action = 'delete'; raise exception 'Anon updated audit row'; exception when insufficient_privilege then null; end;
  begin delete from public.audit_logs; raise exception 'Anon deleted audit row'; exception when insufficient_privilege then null; end;
end;
$$;

rollback;
