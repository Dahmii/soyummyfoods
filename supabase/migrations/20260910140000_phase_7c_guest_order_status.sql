-- Phase 7C.2: capability-authenticated, minimal guest payment-status read.

create or replace function public.get_guest_order_payment_status(
  p_order_id uuid,
  p_payment_capability_hash text
)
returns table (
  order_id uuid,
  order_number text,
  order_status public.order_status,
  payment_status public.payment_status,
  terminal boolean
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
    o.status <> 'pending_payment'::public.order_status
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
