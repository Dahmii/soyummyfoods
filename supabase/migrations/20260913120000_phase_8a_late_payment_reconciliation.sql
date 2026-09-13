-- Phase 8A: manual, internal reconciliation for verified late Stripe successes.
-- This records the operational resolution only; it never changes payment truth,
-- order status, inventory, or Stripe provider state.

alter table public.payments
  add column reconciliation_resolved_at timestamptz,
  add column reconciliation_resolved_by uuid references public.profiles(id) on delete restrict,
  add column reconciliation_resolution_code text,
  add column reconciliation_reference text,
  add column reconciliation_note text,
  add constraint payments_reconciliation_resolution_code_check
    check (reconciliation_resolution_code is null or reconciliation_resolution_code in ('refunded', 'customer_contacted_closed', 'other')),
  add constraint payments_reconciliation_reference_check
    check (reconciliation_reference is null or char_length(reconciliation_reference) between 1 and 255),
  add constraint payments_reconciliation_note_check
    check (reconciliation_note is null or char_length(reconciliation_note) between 1 and 500),
  add constraint payments_reconciliation_fields_check
    check (
      (reconciliation_resolved_at is null
        and reconciliation_resolved_by is null
        and reconciliation_resolution_code is null
        and reconciliation_reference is null
        and reconciliation_note is null)
      or
      (reconciliation_resolved_at is not null
        and reconciliation_resolved_by is not null
        and reconciliation_resolution_code is not null
        and status = 'late_success_requires_reconciliation')
    );

create index payments_late_reconciliation_queue_idx
  on public.payments (provider_succeeded_at, id)
  where status = 'late_success_requires_reconciliation'
    and reconciliation_resolved_at is null;

create or replace function public.resolve_late_payment_reconciliation(
  p_payment_id uuid,
  p_resolution_code text,
  p_reference text default null,
  p_note text default null
)
returns table (
  payment_id uuid,
  reconciliation_resolved_at timestamptz,
  reconciliation_resolved_by uuid,
  reconciliation_resolution_code text,
  reconciliation_reference text,
  reconciliation_note text
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_payment public.payments;
  v_resolution_code text := nullif(lower(btrim(p_resolution_code)), '');
  v_reference text := nullif(btrim(p_reference), '');
  v_note text := nullif(btrim(p_note), '');
begin
  if v_actor_id is null or not public.is_manager_or_owner() then
    raise exception 'Payment reconciliation permission required' using errcode = '42501';
  end if;
  if p_payment_id is null then
    raise exception 'Payment reconciliation input is invalid' using errcode = '22023';
  end if;
  if v_resolution_code is null
     or v_resolution_code not in ('refunded', 'customer_contacted_closed', 'other')
     or (v_reference is not null and char_length(v_reference) > 255)
     or (v_note is not null and char_length(v_note) > 500) then
    raise exception 'Payment reconciliation input is invalid' using errcode = '22023';
  end if;

  select payment_row.* into v_payment
  from public.payments as payment_row
  where payment_row.id = p_payment_id
  for update;
  if not found then
    raise exception 'Payment not found' using errcode = '23503';
  end if;
  if v_payment.status <> 'late_success_requires_reconciliation'::public.payment_status then
    raise exception 'Payment does not require reconciliation' using errcode = '23514';
  end if;
  if v_payment.reconciliation_resolved_at is not null then
    raise exception 'Payment reconciliation has already been resolved' using errcode = '23514';
  end if;

  update public.payments as payment_row
  set reconciliation_resolved_at = now(),
      reconciliation_resolved_by = v_actor_id,
      reconciliation_resolution_code = v_resolution_code,
      reconciliation_reference = v_reference,
      reconciliation_note = v_note
  where payment_row.id = v_payment.id
  returning payment_row.id,
            payment_row.reconciliation_resolved_at,
            payment_row.reconciliation_resolved_by,
            payment_row.reconciliation_resolution_code,
            payment_row.reconciliation_reference,
            payment_row.reconciliation_note
  into payment_id,
       reconciliation_resolved_at,
       reconciliation_resolved_by,
       reconciliation_resolution_code,
       reconciliation_reference,
       reconciliation_note;

  insert into public.audit_logs as audit_entry (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor_id,
    'update',
    'payment',
    v_payment.id,
    jsonb_build_object('status', v_payment.status, 'reconciled', false),
    jsonb_strip_nulls(jsonb_build_object(
      'status', v_payment.status,
      'reconciled', true,
      'reconciliation_resolution_code', v_resolution_code,
      'reconciliation_reference', v_reference
    ))
  );

  return next;
end;
$$;

create or replace function public.list_late_payment_reconciliations(
  p_include_resolved boolean default false
)
returns table (
  payment_id uuid,
  order_id uuid,
  order_number text,
  amount_minor bigint,
  currency_code char(3),
  provider_payment_intent_id text,
  provider_charge_id text,
  provider_succeeded_at timestamptz,
  payment_status public.payment_status,
  reconciled boolean,
  reconciliation_resolved_at timestamptz,
  reconciliation_resolved_by uuid,
  reconciliation_resolution_code text,
  reconciliation_reference text,
  reconciliation_note text,
  order_status public.order_status,
  reservation_expires_at timestamptz,
  cancellation_reason text,
  cancelled_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Payment reconciliation permission required' using errcode = '42501';
  end if;

  return query
  select
    payment_row.id,
    order_row.id,
    order_row.order_number,
    payment_row.amount_minor,
    payment_row.currency_code,
    payment_row.provider_payment_intent_id,
    payment_row.provider_charge_id,
    payment_row.provider_succeeded_at,
    payment_row.status,
    payment_row.reconciliation_resolved_at is not null,
    payment_row.reconciliation_resolved_at,
    payment_row.reconciliation_resolved_by,
    payment_row.reconciliation_resolution_code,
    payment_row.reconciliation_reference,
    payment_row.reconciliation_note,
    order_row.status,
    order_row.reservation_expires_at,
    cancellation_history.reason,
    cancellation_history.created_at
  from public.payments as payment_row
  join public.orders as order_row
    on order_row.id = payment_row.order_id
  left join lateral (
    select history_row.reason, history_row.created_at
    from public.order_status_history as history_row
    where history_row.order_id = order_row.id
      and history_row.previous_status = 'pending_payment'::public.order_status
      and history_row.new_status = 'cancelled'::public.order_status
    order by history_row.created_at desc, history_row.id desc
    limit 1
  ) as cancellation_history on true
  where payment_row.status = 'late_success_requires_reconciliation'::public.payment_status
    and (p_include_resolved or payment_row.reconciliation_resolved_at is null)
  order by payment_row.reconciliation_resolved_at is not null,
           payment_row.provider_succeeded_at nulls last,
           payment_row.id;
end;
$$;

revoke all on function public.resolve_late_payment_reconciliation(uuid, text, text, text) from public;
revoke all on function public.resolve_late_payment_reconciliation(uuid, text, text, text) from anon;
revoke all on function public.resolve_late_payment_reconciliation(uuid, text, text, text) from service_role;
grant execute on function public.resolve_late_payment_reconciliation(uuid, text, text, text) to authenticated;

revoke all on function public.list_late_payment_reconciliations(boolean) from public;
revoke all on function public.list_late_payment_reconciliations(boolean) from anon;
revoke all on function public.list_late_payment_reconciliations(boolean) from service_role;
grant execute on function public.list_late_payment_reconciliations(boolean) to authenticated;
