-- Phase 6: operational admin order reads and controlled status transitions.

create index orders_admin_created_at_id_idx
  on public.orders (created_at desc, id desc);

create index orders_admin_status_created_at_id_idx
  on public.orders (status, created_at desc, id desc);

alter table public.audit_logs drop constraint audit_logs_entity_type_check;
alter table public.audit_logs add constraint audit_logs_entity_type_check
  check (entity_type in ('category', 'product', 'product_image', 'business_settings', 'delivery_zone', 'inventory', 'order'));

grant select on table public.orders, public.order_items, public.order_status_history to authenticated;

create policy "orders_staff_read"
on public.orders for select to authenticated
using (public.is_staff_or_above());

create policy "order_items_staff_read"
on public.order_items for select to authenticated
using (public.is_staff_or_above());

create policy "order_status_history_staff_read"
on public.order_status_history for select to authenticated
using (public.is_staff_or_above());

create or replace function public.get_admin_order_status_history(p_order_id uuid)
returns table (
  id uuid,
  order_id uuid,
  previous_status public.order_status,
  new_status public.order_status,
  actor_user_id uuid,
  actor_display_name text,
  reason text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or not public.is_staff_or_above() then
    raise exception 'Order read permission required' using errcode = '42501';
  end if;

  return query
  select
    history.id,
    history.order_id,
    history.previous_status,
    history.new_status,
    history.actor_user_id,
    case
      when history.actor_user_id is null then 'System'
      when nullif(btrim(profile.display_name), '') is not null then profile.display_name
      else 'Staff'
    end,
    history.reason,
    history.created_at
  from public.order_status_history history
  left join public.profiles profile on profile.id = history.actor_user_id
  where history.order_id = p_order_id
  order by history.created_at asc, history.id asc;
end;
$$;

create or replace function public.transition_admin_order_status(
  p_order_id uuid,
  p_expected_status public.order_status,
  p_next_status public.order_status,
  p_reason text default null
)
returns public.orders
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor_id uuid := auth.uid();
  locked_order public.orders;
  updated_order public.orders;
  normalized_reason text := nullif(btrim(p_reason), '');
  reservation record;
begin
  if actor_id is null or not public.is_staff_or_above() then
    raise exception 'Order management permission required' using errcode = '42501';
  end if;

  select * into locked_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found' using errcode = '23503';
  end if;

  if locked_order.status <> p_expected_status then
    raise exception 'Order status has changed; refresh and try again' using errcode = '40001';
  end if;

  if locked_order.status = 'pending_payment'::public.order_status and p_next_status = 'cancelled'::public.order_status then
    if not public.is_manager_or_owner() then
      raise exception 'Only a manager or owner may cancel a pending order' using errcode = '42501';
    end if;
    if normalized_reason is null or char_length(normalized_reason) > 500 then
      raise exception 'A cancellation reason of at most 500 characters is required' using errcode = '22023';
    end if;

    -- Preserve the Phase 5 lock order: order, products, then inventory.
    perform 1
    from public.products product_row
    join (
      select product_id
      from public.inventory_movements
      where order_id = locked_order.id
        and movement_type in ('order_reservation', 'order_release', 'order_deduction')
      group by product_id
      having sum(reserved_delta) > 0
    ) outstanding on outstanding.product_id = product_row.id
    order by product_row.id
    for share of product_row;

    for reservation in
      select
        inventory_row.id as inventory_id,
        inventory_row.product_id,
        inventory_row.quantity_on_hand,
        inventory_row.quantity_reserved,
        outstanding.reserved_quantity
      from public.inventory inventory_row
      join (
        select inventory_id, product_id, sum(reserved_delta) as reserved_quantity
        from public.inventory_movements
        where order_id = locked_order.id
          and movement_type in ('order_reservation', 'order_release', 'order_deduction')
        group by inventory_id, product_id
        having sum(reserved_delta) > 0
      ) outstanding
        on outstanding.inventory_id = inventory_row.id
       and outstanding.product_id = inventory_row.product_id
      order by inventory_row.product_id
      for update of inventory_row
    loop
      if reservation.quantity_reserved < reservation.reserved_quantity then
        raise exception 'Inventory reservation ledger is inconsistent for order cancellation' using errcode = '23514';
      end if;

      update public.inventory
      set quantity_reserved = quantity_reserved - reservation.reserved_quantity
      where id = reservation.inventory_id
      returning quantity_reserved into reservation.quantity_reserved;

      insert into public.inventory_movements (
        inventory_id,
        product_id,
        movement_type,
        quantity_delta,
        quantity_before,
        quantity_after,
        reserved_delta,
        reserved_before,
        reserved_after,
        order_id,
        reference_type,
        reference_id,
        actor_user_id
      ) values (
        reservation.inventory_id,
        reservation.product_id,
        'order_release',
        0,
        reservation.quantity_on_hand,
        reservation.quantity_on_hand,
        -reservation.reserved_quantity,
        reservation.quantity_reserved + reservation.reserved_quantity,
        reservation.quantity_reserved,
        locked_order.id,
        'order',
        locked_order.id,
        actor_id
      );
    end loop;
  elsif (locked_order.status = 'confirmed'::public.order_status and p_next_status = 'preparing'::public.order_status)
     or (locked_order.status = 'preparing'::public.order_status and p_next_status = 'ready'::public.order_status)
     or (locked_order.status = 'ready'::public.order_status and p_next_status = 'completed'::public.order_status) then
    normalized_reason := null;
  else
    raise exception 'This order status transition is not allowed' using errcode = '23514';
  end if;

  update public.orders
  set status = p_next_status,
      updated_at = now()
  where id = locked_order.id
  returning * into updated_order;

  insert into public.order_status_history (
    order_id,
    previous_status,
    new_status,
    actor_user_id,
    reason
  ) values (
    updated_order.id,
    locked_order.status,
    updated_order.status,
    actor_id,
    normalized_reason
  );

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    old_values,
    new_values
  ) values (
    actor_id,
    'update',
    'order',
    updated_order.id,
    jsonb_build_object('status', locked_order.status),
    case
      when normalized_reason is null then jsonb_build_object('status', updated_order.status)
      else jsonb_build_object('status', updated_order.status, 'reason', normalized_reason)
    end
  );

  return updated_order;
end;
$$;

revoke all on function public.get_admin_order_status_history(uuid) from public;
revoke all on function public.get_admin_order_status_history(uuid) from anon;
grant execute on function public.get_admin_order_status_history(uuid) to authenticated;

revoke all on function public.transition_admin_order_status(uuid, public.order_status, public.order_status, text) from public;
revoke all on function public.transition_admin_order_status(uuid, public.order_status, public.order_status, text) from anon;
revoke all on function public.transition_admin_order_status(uuid, public.order_status, public.order_status, text) from service_role;
grant execute on function public.transition_admin_order_status(uuid, public.order_status, public.order_status, text) to authenticated;
