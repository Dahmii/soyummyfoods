-- Phase 10C: narrow, staff-safe payment context for an existing admin order.
-- Direct payments-table access remains restricted to managers and owners.

create function public.get_admin_order_payment_summary(p_order_id uuid)
returns table (
  order_id uuid,
  payment_status public.payment_status,
  amount_minor bigint,
  currency_code char(3),
  provider public.payment_provider,
  paid_at timestamptz,
  requires_manager_review boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.is_staff_or_above() then
    raise exception 'Order payment summary permission required' using errcode = '42501';
  end if;

  if p_order_id is null then
    raise exception 'Order payment summary input is invalid' using errcode = '22023';
  end if;

  -- A late success remains exceptional even if a historical successful attempt
  -- exists. Otherwise, a verified success takes precedence; absent one, the
  -- highest attempt sequence communicates the latest pending/failed context.
  -- No payment attempt deliberately returns zero rows.
  return query
  select
    payment_row.order_id,
    payment_row.status,
    payment_row.amount_minor,
    payment_row.currency_code,
    payment_row.provider,
    payment_row.provider_succeeded_at,
    payment_row.status = 'late_success_requires_reconciliation'::public.payment_status
      and payment_row.reconciliation_resolved_at is null
  from public.payments as payment_row
  where payment_row.order_id = p_order_id
  order by case
             when payment_row.status = 'late_success_requires_reconciliation'::public.payment_status then 0
             when payment_row.status = 'succeeded'::public.payment_status then 1
             else 2
           end,
           payment_row.attempt_sequence desc,
           payment_row.id desc
  limit 1;
end;
$$;

revoke all on function public.get_admin_order_payment_summary(uuid) from public;
revoke all on function public.get_admin_order_payment_summary(uuid) from anon;
revoke all on function public.get_admin_order_payment_summary(uuid) from service_role;
grant execute on function public.get_admin_order_payment_summary(uuid) to authenticated;
