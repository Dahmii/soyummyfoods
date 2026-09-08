-- Phase 2A catalogue verification. Run after applying Phase 1 and Phase 2A.
-- Replace the UUID placeholders with existing Auth user IDs that have the stated roles.

begin;

set local role authenticated;

-- Owner: helper evaluation must work without recursive RLS and catalogue counts must match.
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
begin
  if not public.has_role('owner'::public.app_role) then
    raise exception 'Owner role helper test failed';
  end if;
  if (select count(*) from public.categories) <> 7 then
    raise exception 'Expected exactly seven seeded categories';
  end if;
  if (select count(*) from public.products) <> 41 then
    raise exception 'Expected exactly 41 seeded products';
  end if;
  if (select count(*) from public.product_images) <> 41 then
    raise exception 'Expected exactly 41 seeded product images';
  end if;
  if exists (
    select 1 from public.products p
    left join public.categories c on c.id = p.category_id
    where c.id is null
  ) then
    raise exception 'Product without a valid category relationship found';
  end if;
  if exists (select slug from public.products group by slug having count(*) > 1) then
    raise exception 'Duplicate product slug found';
  end if;
  if not exists (
    select 1 from public.products
    where slug = 'coconut-rice'
      and base_price is null
      and price_on_request
      and sale_price is null
  ) then
    raise exception 'Coconut Rice price-on-request seed is incorrect';
  end if;
  if exists (
    select 1 from public.products
    where slug <> 'coconut-rice'
      and (base_price is null or price_on_request or sale_price is not null)
  ) then
    raise exception 'Fixed-price product seed is incorrect';
  end if;
  begin
    insert into public.products (
      category_id, slug, name, description, base_price, sale_price,
      price_on_request, prep_time_minutes, status, display_order
    )
    select id, 'phase-2a-invalid-por-sale-price', 'Invalid POR price test',
      'Temporary verification product.', null, 1, true, 1, 'draft', 10000
    from public.categories where slug = 'rice-dishes';
    raise exception 'Price-on-request product unexpectedly accepted a sale price';
  exception when check_violation then
    null;
  end;
  if exists (
    select 1 from public.products p
    left join public.product_images image
      on image.product_id = p.id and image.is_primary
    where image.id is null
  ) then
    raise exception 'A seeded product has no primary image';
  end if;
  if not exists (
    select 1 from public.products p
    join public.product_images image on image.product_id = p.id
    where p.slug = 'jollof-rice'
      and image.is_primary
      and image.storage_path = '/4474ba82-cf02-4264-9b7b-24159e623a2a.jpg'
  ) then
    raise exception 'Jollof Rice primary image path was not preserved';
  end if;
end;
$$;

-- Add non-seeded rows only inside this transaction to exercise public visibility.
insert into public.products (
  category_id, slug, name, description, base_price, prep_time_minutes,
  status, is_available, display_order
)
select id, 'phase-2a-active-unavailable-test', 'Phase 2A active unavailable test',
  'Temporary verification product.', 1, 1, 'active', false, 9998
from public.categories where slug = 'rice-dishes';

insert into public.products (
  category_id, slug, name, description, base_price, prep_time_minutes,
  status, is_available, display_order
)
select id, 'phase-2a-draft-test', 'Phase 2A draft test',
  'Temporary verification product.', 1, 1, 'draft', true, 9999
from public.categories where slug = 'rice-dishes';

-- Anonymous users can read active data, including unavailable products, but not drafts or writes.
set local role anon;
do $$
begin
  if not exists (select 1 from public.categories where slug = 'rice-dishes') then
    raise exception 'Anonymous active-category read failed';
  end if;
  if not exists (
    select 1 from public.products where slug = 'phase-2a-active-unavailable-test'
  ) then
    raise exception 'Anonymous active unavailable-product read failed';
  end if;
  if exists (select 1 from public.products where slug = 'phase-2a-draft-test') then
    raise exception 'Anonymous read exposed a draft product';
  end if;
  begin
    update public.products set name = 'Unexpected anon write' where slug = 'jollof-rice';
    raise exception 'Anonymous user unexpectedly updated products';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Staff can read active catalogue rows but cannot manage them.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
begin
  if not exists (select 1 from public.products where slug = 'jollof-rice') then
    raise exception 'Staff active-product read failed';
  end if;
  begin
    update public.products set name = 'Unexpected staff write' where slug = 'jollof-rice';
    if found then raise exception 'Staff unexpectedly updated products'; end if;
  end;
  begin
    update public.categories set name = 'Unexpected staff write' where slug = 'rice-dishes';
    if found then raise exception 'Staff unexpectedly updated categories'; end if;
  end;
  begin
    update public.product_images set alt_text = 'Unexpected staff write'
    where product_id = (select id from public.products where slug = 'jollof-rice');
    if found then raise exception 'Staff unexpectedly updated product images'; end if;
  end;
end;
$$;

-- Manager has catalogue-management access; the transaction rollback keeps seed data unchanged.
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
begin
  if not public.is_manager_or_owner() then
    raise exception 'Manager role helper test failed';
  end if;
  update public.categories set description = 'Phase 2A manager verification'
  where slug = 'rice-dishes';
  update public.products set portion_note = 'Phase 2A manager verification'
  where slug = 'jollof-rice';
  update public.product_images set alt_text = 'Phase 2A manager verification'
  where product_id = (select id from public.products where slug = 'jollof-rice') and is_primary;
end;
$$;

rollback;
