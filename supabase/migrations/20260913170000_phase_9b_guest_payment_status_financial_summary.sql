-- Phase 9B: capability-gated, minimal authoritative financial confirmation.
-- The return signature changes, so PostgreSQL requires replacing the existing
-- service-only RPC rather than using CREATE OR REPLACE.

drop function public.get_guest_order_payment_status(uuid, text);

create function public.get_guest_order_payment_status(
  p_order_id uuid,
  p_payment_capability_hash text
)
returns table (
  order_id uuid,
  order_number text,
  order_status public.order_status,
  payment_status public.payment_status,
  terminal boolean,
  subtotal numeric,
  delivery_fee numeric,
  discount_amount numeric,
  tax_amount numeric,
  total numeric,
  currency_code char(3),
  reservation_expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_order_id is null or p_payment_capability_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'guest_order_status_unavailable' using errcode = '22023';
  end if;

  return query
  select
    o.id,
    o.order_number,
    o.status,
    p.status,
    o.status <> 'pending_payment'::public.order_status,
    o.subtotal,
    o.delivery_fee,
    o.discount_amount,
    o.tax_amount,
    o.total,
    o.currency_code,
    o.reservation_expires_at
  from public.orders as o
  join public.payments as p
    on p.order_id = o.id
  where o.id = p_order_id
    and p.payment_capability_hash = p_payment_capability_hash
  order by p.attempt_sequence desc
  limit 1;
end;
$$;

revoke all on function public.get_guest_order_payment_status(uuid, text) from public;
revoke all on function public.get_guest_order_payment_status(uuid, text) from anon;
revoke all on function public.get_guest_order_payment_status(uuid, text) from authenticated;
grant execute on function public.get_guest_order_payment_status(uuid, text) to service_role;
