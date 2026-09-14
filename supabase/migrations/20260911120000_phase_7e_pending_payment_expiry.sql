-- Phase 7E: bounded, database-scheduled expiry of abandoned pending payments.
-- The existing expire_pending_order(uuid) remains the sole cancellation/release primitive.

create or replace function public.expire_overdue_pending_orders(
  p_batch_size integer default 50
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  candidate record;
  expired_count integer := 0;
begin
  if p_batch_size is null or p_batch_size not between 1 and 100 then
    raise exception 'Expiry batch size must be between 1 and 100' using errcode = '22023';
  end if;

  for candidate in
    select order_row.id
    from public.orders as order_row
    where order_row.status = 'pending_payment'::public.order_status
      and order_row.reservation_expires_at <= now()
    order by order_row.reservation_expires_at, order_row.id
    limit p_batch_size
    for update skip locked
  loop
    perform public.expire_pending_order(candidate.id);
    expired_count := expired_count + 1;
  end loop;

  return expired_count;
end;
$$;

revoke all on function public.expire_overdue_pending_orders(integer) from public;
revoke all on function public.expire_overdue_pending_orders(integer) from anon;
revoke all on function public.expire_overdue_pending_orders(integer) from authenticated;
