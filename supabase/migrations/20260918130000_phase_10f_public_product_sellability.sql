-- Phase 10F: expose a public, boolean-only ordering snapshot without exposing
-- operational inventory balances or movement history.

create function public.get_public_product_sellability()
returns table (
  product_id uuid,
  is_orderable boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    product_row.id,
    product_row.is_available
      and not product_row.price_on_request
      and product_row.base_price is not null
      and (
        inventory_row.product_id is null
        or not inventory_row.is_tracking_enabled
        or inventory_row.quantity_on_hand - inventory_row.quantity_reserved > 0
      )
  from public.products as product_row
  join public.categories as category_row
    on category_row.id = product_row.category_id
  left join public.inventory as inventory_row
    on inventory_row.product_id = product_row.id
  where product_row.status = 'active'::public.product_status
    and category_row.is_active;
$$;

revoke all on function public.get_public_product_sellability() from public;
revoke all on function public.get_public_product_sellability() from anon;
revoke all on function public.get_public_product_sellability() from authenticated;
revoke all on function public.get_public_product_sellability() from service_role;
grant execute on function public.get_public_product_sellability() to anon, authenticated;
