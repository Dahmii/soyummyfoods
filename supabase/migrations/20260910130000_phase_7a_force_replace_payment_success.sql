-- Force-replace the canonical Phase 7A success processor. RETURNS TABLE makes
-- `payment_id` and `order_id` PL/pgSQL variables, so every relation reference
-- below uses an explicit alias and every readable column is qualified.

create or replace function public.process_verified_stripe_payment_success(
  p_provider_event_id text,
  p_provider_payment_intent_id text,
  p_provider_charge_id text,
  p_payment_id uuid,
  p_order_id uuid,
  p_verified_amount_minor bigint,
  p_verified_currency text,
  p_provider_created_at timestamptz,
  p_payload_sha256 text
)
returns table (outcome text, payment_id uuid, order_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  inserted_event_id uuid;
  locked_order public.orders;
  locked_payment public.payments;
  reservation record;
  normalized_currency text := upper(btrim(p_verified_currency));
begin
  if nullif(btrim(p_provider_event_id), '') is null or nullif(btrim(p_provider_payment_intent_id), '') is null or p_verified_amount_minor is null or p_verified_amount_minor <= 0 or p_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid verified Stripe payment input' using errcode = '22023';
  end if;

  insert into public.payment_provider_events as provider_event (provider, provider_event_id, event_type, provider_object_id, provider_created_at, payload_sha256)
  values ('stripe', btrim(p_provider_event_id), 'payment_intent.succeeded', btrim(p_provider_payment_intent_id), p_provider_created_at, p_payload_sha256)
  on conflict (provider, provider_event_id) do nothing
  returning provider_event.id into inserted_event_id;
  if inserted_event_id is null then
    return query select 'duplicate', p_payment_id, p_order_id;
    return;
  end if;

  select order_row.* into locked_order
  from public.orders as order_row
  where order_row.id = p_order_id
  for update;
  if not found then
    update public.payment_provider_events as provider_event
    set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch'
    where provider_event.id = inserted_event_id;
    return query select 'rejected', p_payment_id, p_order_id;
    return;
  end if;

  select payment_row.* into locked_payment
  from public.payments as payment_row
  where payment_row.id = p_payment_id
  for update;
  if not found or locked_order.id <> locked_payment.order_id or locked_payment.provider <> 'stripe' or locked_payment.provider_payment_intent_id <> btrim(p_provider_payment_intent_id) or locked_payment.amount_minor <> p_verified_amount_minor or normalized_currency <> 'GBP' or locked_payment.currency_code <> 'GBP' or (locked_payment.provider_charge_id is not null and nullif(btrim(p_provider_charge_id), '') is not null and locked_payment.provider_charge_id <> btrim(p_provider_charge_id)) then
    update public.payment_provider_events as provider_event
    set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch'
    where provider_event.id = inserted_event_id;
    return query select 'rejected', p_payment_id, p_order_id;
    return;
  end if;

  update public.payment_provider_events as provider_event
  set payment_id = locked_payment.id, order_id = locked_order.id
  where provider_event.id = inserted_event_id;
  if locked_payment.status = 'succeeded' and locked_order.status = 'confirmed' then
    update public.payment_provider_events as provider_event
    set processed_at = now(), processing_outcome = 'duplicate'
    where provider_event.id = inserted_event_id;
    return query select 'duplicate', locked_payment.id, locked_order.id;
    return;
  end if;

  if locked_order.status = 'pending_payment'
     and locked_payment.status not in ('awaiting_payment_intent', 'payment_intent_attached', 'payment_failed') then
    update public.payment_provider_events as provider_event
    set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_state_invalid'
    where provider_event.id = inserted_event_id;
    return query select 'rejected', locked_payment.id, locked_order.id;
    return;
  end if;

  if locked_order.status = 'pending_payment' and locked_order.reservation_expires_at <= now() then
    perform public.expire_pending_order(locked_order.id);
    select order_row.* into locked_order
    from public.orders as order_row
    where order_row.id = p_order_id
    for update;
  end if;
  if locked_order.status <> 'pending_payment' then
    update public.payments as payment_row
    set status = 'late_success_requires_reconciliation', provider_charge_id = coalesce(nullif(btrim(p_provider_charge_id), ''), payment_row.provider_charge_id), provider_succeeded_at = coalesce(p_provider_created_at, now()), provider_failure_code = null
    where payment_row.id = locked_payment.id;
    update public.payment_provider_events as provider_event
    set processed_at = now(), processing_outcome = 'late_success_requires_reconciliation'
    where provider_event.id = inserted_event_id;
    insert into public.audit_logs as audit_entry (actor_user_id, action, entity_type, entity_id, old_values, new_values)
    values (null, 'update', 'payment', locked_payment.id, jsonb_build_object('status', locked_payment.status), jsonb_build_object('status', 'late_success_requires_reconciliation', 'provider', 'stripe'));
    return query select 'late_success_requires_reconciliation', locked_payment.id, locked_order.id;
    return;
  end if;

  perform 1
  from public.products as product_row
  join (
    select im.product_id
    from public.inventory_movements as im
    where im.order_id = locked_order.id
      and im.movement_type in ('order_reservation', 'order_release', 'order_deduction')
    group by im.product_id
    having sum(im.reserved_delta) > 0
  ) as outstanding on outstanding.product_id = product_row.id
  order by product_row.id
  for share of product_row;

  -- Preflight every locked reservation before mutating any balance. Expected
  -- ledger inconsistencies are durably rejected with no partial deduction;
  -- unexpected database failures still abort and remain retryable.
  for reservation in
    select inventory_row.id as inventory_id, inventory_row.product_id, inventory_row.quantity_on_hand, inventory_row.quantity_reserved, outstanding.reserved_quantity
    from public.inventory as inventory_row
    join (
      select im.inventory_id, im.product_id, sum(im.reserved_delta) as reserved_quantity
      from public.inventory_movements as im
      where im.order_id = locked_order.id
        and im.movement_type in ('order_reservation', 'order_release', 'order_deduction')
      group by im.inventory_id, im.product_id
      having sum(im.reserved_delta) > 0
    ) as outstanding on outstanding.inventory_id = inventory_row.id and outstanding.product_id = inventory_row.product_id
    order by inventory_row.product_id
    for update of inventory_row
  loop
    if reservation.quantity_reserved < reservation.reserved_quantity or reservation.quantity_on_hand < reservation.reserved_quantity then
      update public.payment_provider_events as provider_event
      set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'inventory_ledger_inconsistent'
      where provider_event.id = inserted_event_id;
      return query select 'rejected', locked_payment.id, locked_order.id;
      return;
    end if;
  end loop;

  for reservation in
    select inventory_row.id as inventory_id, inventory_row.product_id, inventory_row.quantity_on_hand, inventory_row.quantity_reserved, outstanding.reserved_quantity
    from public.inventory as inventory_row
    join (
      select im.inventory_id, im.product_id, sum(im.reserved_delta) as reserved_quantity
      from public.inventory_movements as im
      where im.order_id = locked_order.id
        and im.movement_type in ('order_reservation', 'order_release', 'order_deduction')
      group by im.inventory_id, im.product_id
      having sum(im.reserved_delta) > 0
    ) as outstanding on outstanding.inventory_id = inventory_row.id and outstanding.product_id = inventory_row.product_id
    order by inventory_row.product_id
    for update of inventory_row
  loop
    update public.inventory as inventory_row
    set quantity_on_hand = inventory_row.quantity_on_hand - reservation.reserved_quantity,
        quantity_reserved = inventory_row.quantity_reserved - reservation.reserved_quantity
    where inventory_row.id = reservation.inventory_id;
    insert into public.inventory_movements as inventory_movement (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
    values (reservation.inventory_id, reservation.product_id, 'order_deduction', -reservation.reserved_quantity, reservation.quantity_on_hand, reservation.quantity_on_hand - reservation.reserved_quantity, -reservation.reserved_quantity, reservation.quantity_reserved, reservation.quantity_reserved - reservation.reserved_quantity, locked_order.id, 'order', locked_order.id);
  end loop;

  update public.payments as payment_row
  set status = 'succeeded', provider_charge_id = coalesce(nullif(btrim(p_provider_charge_id), ''), payment_row.provider_charge_id), provider_succeeded_at = coalesce(p_provider_created_at, now()), provider_failure_code = null
  where payment_row.id = locked_payment.id;
  update public.orders as order_row
  set status = 'confirmed', updated_at = now()
  where order_row.id = locked_order.id;
  insert into public.order_status_history as status_history (order_id, previous_status, new_status, actor_user_id, reason)
  values (locked_order.id, 'pending_payment', 'confirmed', null, 'stripe_payment_succeeded');
  insert into public.audit_logs as audit_entry (actor_user_id, action, entity_type, entity_id, old_values, new_values)
  values (null, 'update', 'order', locked_order.id, jsonb_build_object('status', 'pending_payment'), jsonb_build_object('status', 'confirmed', 'payment_provider', 'stripe'));
  update public.payment_provider_events as provider_event
  set processed_at = now(), processing_outcome = 'processed'
  where provider_event.id = inserted_event_id;
  return query select 'processed', locked_payment.id, locked_order.id;
end;
$$;
