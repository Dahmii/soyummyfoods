-- Safe catalog removal: retain products that have operational history and
-- permanently remove only products that have never been used operationally.

create or replace function public.get_admin_product_removal_plan(
  p_product_id uuid
)
returns table(removal_action text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Catalog management permission required' using errcode = '42501';
  end if;

  if p_product_id is null then
    raise exception 'Product ID is required' using errcode = '22023';
  end if;

  if not exists (select 1 from public.products as product_row where product_row.id = p_product_id) then
    raise exception 'Product not found' using errcode = '23503';
  end if;

  return query
  select case
    when exists (
      select 1
      from public.order_items as order_item
      where order_item.product_id = p_product_id
    ) or exists (
      select 1
      from public.inventory_movements as movement
      where movement.product_id = p_product_id
    ) or exists (
      select 1
      from public.inventory as inventory_row
      where inventory_row.product_id = p_product_id
        and (inventory_row.quantity_on_hand <> 0 or inventory_row.quantity_reserved <> 0)
    ) then 'archive'
    else 'delete'
  end;
end;
$$;

create or replace function public.remove_admin_product(
  p_product_id uuid
)
returns table(removal_action text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_has_operational_history boolean;
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Catalog management permission required' using errcode = '42501';
  end if;

  if p_product_id is null then
    raise exception 'Product ID is required' using errcode = '22023';
  end if;

  -- This lock conflicts with checkout and inventory operations, which acquire
  -- a shared product lock before they create an order or inventory movement.
  perform 1
  from public.products as product_row
  where product_row.id = p_product_id
  for update;
  if not found then
    raise exception 'Product not found' using errcode = '23503';
  end if;

  select exists (
    select 1
    from public.order_items as order_item
    where order_item.product_id = p_product_id
  ) or exists (
    select 1
    from public.inventory_movements as movement
    where movement.product_id = p_product_id
  ) or exists (
    select 1
    from public.inventory as inventory_row
    where inventory_row.product_id = p_product_id
      and (inventory_row.quantity_on_hand <> 0 or inventory_row.quantity_reserved <> 0)
  ) into v_has_operational_history;

  if v_has_operational_history then
    update public.products
    set status = 'archived'::public.product_status,
        is_available = false
    where id = p_product_id;

    return query select 'archived'::text;
    return;
  end if;

  -- A configuration row with no immutable movements is not history. Remove it
  -- before the product because inventory.product_id is intentionally RESTRICT.
  delete from public.inventory as inventory_row
  where inventory_row.product_id = p_product_id;

  -- product_images metadata cascades by its existing foreign key. This function
  -- deliberately makes no Storage API call, so uploaded objects remain intact.
  delete from public.products as product_row
  where product_row.id = p_product_id;

  return query select 'deleted'::text;
end;
$$;

revoke all on function public.get_admin_product_removal_plan(uuid) from public;
revoke all on function public.get_admin_product_removal_plan(uuid) from anon;
revoke all on function public.get_admin_product_removal_plan(uuid) from authenticated;
revoke all on function public.get_admin_product_removal_plan(uuid) from service_role;
grant execute on function public.get_admin_product_removal_plan(uuid) to authenticated;

revoke all on function public.remove_admin_product(uuid) from public;
revoke all on function public.remove_admin_product(uuid) from anon;
revoke all on function public.remove_admin_product(uuid) from authenticated;
revoke all on function public.remove_admin_product(uuid) from service_role;
grant execute on function public.remove_admin_product(uuid) to authenticated;

comment on function public.get_admin_product_removal_plan(uuid) is
  'Manager/owner-only preview. Products with order-item or inventory-movement history, or nonzero current stock, must be archived.';
comment on function public.remove_admin_product(uuid) is
  'Manager/owner-only atomic product removal. Archives products with operational history; otherwise removes the product and empty inventory configuration without touching Storage objects.';
