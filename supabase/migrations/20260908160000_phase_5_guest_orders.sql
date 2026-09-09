-- Phase 5: authoritative guest orders and pending-payment stock reservations.

create type public.order_status as enum ('pending_payment', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique check (order_number ~ '^SYF-[0-9]{8}-[A-F0-9]{8}$'),
  idempotency_key uuid not null unique,
  request_fingerprint text not null,
  status public.order_status not null default 'pending_payment',
  customer_name text not null check (char_length(customer_name) between 2 and 100),
  customer_email text not null check (char_length(customer_email) <= 254),
  customer_phone text not null check (char_length(customer_phone) between 7 and 32),
  delivery_address text not null check (char_length(delivery_address) between 6 and 500),
  postcode_snapshot text not null check (char_length(postcode_snapshot) between 2 and 16),
  delivery_zone_id uuid references public.delivery_zones(id) on delete restrict,
  delivery_zone_name_snapshot text not null,
  subtotal numeric(10,2) not null check (subtotal >= 0),
  delivery_fee numeric(10,2) not null check (delivery_fee >= 0),
  discount_amount numeric(10,2) not null default 0 check (discount_amount = 0),
  tax_amount numeric(10,2) not null default 0 check (tax_amount >= 0),
  tax_label_snapshot text,
  tax_rate_percent_snapshot numeric(5,2),
  total numeric(10,2) not null check (total = subtotal - discount_amount + delivery_fee + tax_amount),
  currency_code char(3) not null default 'GBP' check (currency_code = 'GBP'),
  customer_note text check (customer_note is null or char_length(customer_note) <= 500),
  reservation_expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_pending_expiry_idx on public.orders (reservation_expires_at) where status = 'pending_payment';

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  product_slug_snapshot text not null,
  product_name_snapshot text not null,
  portion_note_snapshot text,
  quantity integer not null check (quantity between 1 and 99),
  unit_price numeric(10,2) not null check (unit_price >= 0),
  line_subtotal numeric(10,2) not null check (line_subtotal = quantity * unit_price),
  created_at timestamptz not null default now()
);
create index order_items_order_idx on public.order_items(order_id);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  previous_status public.order_status,
  new_status public.order_status not null,
  actor_user_id uuid references public.profiles(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);
create index order_status_history_order_idx on public.order_status_history(order_id, created_at);

alter table public.inventory add column quantity_reserved integer not null default 0;
alter table public.inventory add constraint inventory_reserved_nonnegative check (quantity_reserved >= 0);
alter table public.inventory add constraint inventory_reserved_within_on_hand check (quantity_reserved <= quantity_on_hand);

alter table public.inventory_movements add column reserved_delta integer not null default 0;
alter table public.inventory_movements add column reserved_before integer not null default 0;
alter table public.inventory_movements add column reserved_after integer not null default 0;
alter table public.inventory_movements add column order_id uuid references public.orders(id) on delete restrict;
alter table public.inventory_movements drop constraint inventory_movements_quantity_delta_check;
alter table public.inventory_movements add constraint inventory_movements_nonzero_balance_delta check (quantity_delta <> 0 or reserved_delta <> 0);
alter table public.inventory_movements add constraint inventory_movements_reserved_math check (reserved_after = reserved_before + reserved_delta and reserved_before >= 0 and reserved_after >= 0 and reserved_after <= quantity_after);
alter table public.inventory_movements drop constraint inventory_movements_movement_type_check;
alter table public.inventory_movements add constraint inventory_movements_movement_type_check check (movement_type in ('stock_added','manual_adjustment','waste','order_deduction','order_restock','order_reservation','order_release'));
-- Phase 4 exposed order_deduction as a reserved type but did not have orders.
-- Never fabricate order links for any historical trusted rows.
do $$
begin
  if exists (select 1 from public.inventory_movements where movement_type = 'order_deduction') then
    raise exception 'Phase 5 cannot add typed order linkage while historical order_deduction movements exist; reconcile those rows before applying this migration' using errcode = '23514';
  end if;
end;
$$;
alter table public.inventory_movements add constraint inventory_movements_order_linkage check ((movement_type in ('order_reservation','order_release','order_deduction') and order_id is not null and reference_type = 'order' and reference_id = order_id) or (movement_type not in ('order_reservation','order_release','order_deduction') and order_id is null));
alter table public.inventory_movements add constraint inventory_movements_balance_semantics check (
  (movement_type = 'order_reservation' and quantity_delta = 0 and reserved_delta > 0)
  or (movement_type = 'order_release' and quantity_delta = 0 and reserved_delta < 0)
  or (movement_type = 'order_deduction' and quantity_delta < 0 and reserved_delta < 0)
  or (movement_type in ('stock_added', 'manual_adjustment', 'waste', 'order_restock') and reserved_delta = 0)
);

create or replace function public.create_guest_order(p_payload jsonb)
returns table(order_id uuid, order_number text, subtotal numeric, delivery_fee numeric, discount_amount numeric, tax_amount numeric, total numeric, currency_code char(3), status public.order_status, reservation_expires_at timestamptz)
language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_key uuid := (p_payload->>'idempotency_key')::uuid; v_lines jsonb := p_payload->'lines'; v_fingerprint text; v_order public.orders; v_zone record; v_settings public.business_settings; v_subtotal numeric(10,2); v_product record; v_line record; v_inventory public.inventory; v_count integer;
begin
  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) not between 1 and 20 then raise exception 'invalid_cart' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_key::text, 5));
  v_fingerprint := md5(jsonb_build_object('lines', (select jsonb_agg(jsonb_build_object('product_id', product_id, 'quantity', quantity) order by product_id) from (select (value->>'product_id')::uuid product_id, sum((value->>'quantity')::integer) quantity from jsonb_array_elements(v_lines) group by 1) normalized), 'name', btrim(p_payload->>'customer_name'), 'email', lower(btrim(p_payload->>'customer_email')), 'phone', btrim(p_payload->>'customer_phone'), 'address', btrim(p_payload->>'delivery_address'), 'postcode', public.normalize_postcode(p_payload->>'postcode'), 'note', nullif(btrim(p_payload->>'customer_note'),''))::text);
  select * into v_order from public.orders where idempotency_key = v_key;
  if found then if v_order.request_fingerprint <> v_fingerprint then raise exception 'idempotency_conflict' using errcode='22023'; end if; return query select v_order.id,v_order.order_number,v_order.subtotal,v_order.delivery_fee,v_order.discount_amount,v_order.tax_amount,v_order.total,v_order.currency_code,v_order.status,v_order.reservation_expires_at; return; end if;
  if char_length(btrim(p_payload->>'customer_name')) not between 2 and 100 or char_length(btrim(p_payload->>'customer_email')) not between 3 and 254 or char_length(btrim(p_payload->>'customer_phone')) not between 7 and 32 or char_length(btrim(p_payload->>'delivery_address')) not between 6 and 500 or char_length(coalesce(p_payload->>'customer_note','')) > 500 then raise exception 'invalid_customer_details' using errcode='22023'; end if;
  create temporary table if not exists checkout_lines(product_id uuid primary key, quantity integer not null check(quantity between 1 and 99)) on commit drop;
  truncate checkout_lines;
  insert into checkout_lines select (value->>'product_id')::uuid, sum((value->>'quantity')::integer) from jsonb_array_elements(v_lines) group by 1;
  if exists(select 1 from checkout_lines where quantity not between 1 and 99) then raise exception 'invalid_quantity' using errcode='22023'; end if;
  -- Product lifecycle/pricing locks are acquired before inventory locks, ordered by UUID.
  for v_product in select p.* from public.products p join checkout_lines l on l.product_id=p.id order by p.id for share loop
    if v_product.status <> 'active' or not v_product.is_available or v_product.price_on_request or v_product.base_price is null then raise exception 'product_unavailable' using errcode='23514'; end if;
  end loop;
  if (select count(*) from checkout_lines) <> (select count(*) from public.products p join checkout_lines l on l.product_id=p.id) then raise exception 'product_not_found' using errcode='23503'; end if;
  select round(sum(l.quantity * coalesce(p.sale_price,p.base_price)),2) into v_subtotal from checkout_lines l join public.products p on p.id=l.product_id;
  select * into v_zone from public.resolve_active_delivery_zone(p_payload->>'postcode'); if not found then raise exception 'unsupported_delivery_area' using errcode='23514'; end if;
  select * into v_settings from public.business_settings where id=1 for share;
  if v_settings.tax_enabled then raise exception 'tax_configuration_required' using errcode='23514'; end if;
  if v_zone.minimum_order is not null and v_subtotal < v_zone.minimum_order then raise exception 'minimum_order_not_met' using errcode='23514'; end if;
  perform 1 from public.delivery_zones where id=v_zone.zone_id and is_active for share; if not found then raise exception 'unsupported_delivery_area' using errcode='23514'; end if;
  for v_inventory in select i.* from public.inventory i join checkout_lines l on l.product_id=i.product_id where i.is_tracking_enabled order by i.product_id for update loop
    select * into v_line from checkout_lines where product_id=v_inventory.product_id;
    if v_inventory.quantity_on_hand - v_inventory.quantity_reserved < v_line.quantity then raise exception 'insufficient_stock' using errcode='23514'; end if;
  end loop;
  insert into public.orders(order_number,idempotency_key,request_fingerprint,status,customer_name,customer_email,customer_phone,delivery_address,postcode_snapshot,delivery_zone_id,delivery_zone_name_snapshot,subtotal,delivery_fee,tax_amount,total,customer_note,reservation_expires_at)
  values ('SYF-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),v_key,v_fingerprint,'pending_payment',btrim(p_payload->>'customer_name'),lower(btrim(p_payload->>'customer_email')),btrim(p_payload->>'customer_phone'),btrim(p_payload->>'delivery_address'),v_zone.normalized_postcode,v_zone.zone_id,v_zone.zone_name,v_subtotal,v_zone.delivery_fee,0,v_subtotal+v_zone.delivery_fee,nullif(btrim(p_payload->>'customer_note'),''),now()+interval '15 minutes') returning * into v_order;
  insert into public.order_items(order_id,product_id,product_slug_snapshot,product_name_snapshot,portion_note_snapshot,quantity,unit_price,line_subtotal) select v_order.id,p.id,p.slug,p.name,p.portion_note,l.quantity,coalesce(p.sale_price,p.base_price),l.quantity*coalesce(p.sale_price,p.base_price) from checkout_lines l join public.products p on p.id=l.product_id;
  for v_inventory in select i.* from public.inventory i join checkout_lines l on l.product_id=i.product_id where i.is_tracking_enabled order by i.product_id for update loop
    select * into v_line from checkout_lines where product_id=v_inventory.product_id;
    update public.inventory set quantity_reserved=quantity_reserved+v_line.quantity where id=v_inventory.id returning * into v_inventory;
    insert into public.inventory_movements(inventory_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reserved_delta,reserved_before,reserved_after,order_id,reference_type,reference_id) values(v_inventory.id,v_inventory.product_id,'order_reservation',0,v_inventory.quantity_on_hand,v_inventory.quantity_on_hand,v_line.quantity,v_inventory.quantity_reserved-v_line.quantity,v_inventory.quantity_reserved,v_order.id,'order',v_order.id);
  end loop;
  insert into public.order_status_history(order_id,new_status) values(v_order.id,'pending_payment');
  return query select v_order.id,v_order.order_number,v_order.subtotal,v_order.delivery_fee,v_order.discount_amount,v_order.tax_amount,v_order.total,v_order.currency_code,v_order.status,v_order.reservation_expires_at;
end; $$;

alter table public.orders enable row level security; alter table public.order_items enable row level security; alter table public.order_status_history enable row level security;
revoke all on table public.orders, public.order_items, public.order_status_history from anon, authenticated;
revoke all on function public.create_guest_order(jsonb) from public, anon, authenticated;
grant execute on function public.create_guest_order(jsonb) to service_role;

-- Preserve the Phase 4 product -> inventory lock ordering while recording the
-- reservation balance on every new physical movement.
create or replace function public.adjust_inventory(
  p_inventory_id uuid,
  p_movement_type text,
  p_quantity_delta integer,
  p_note text default null
)
returns public.inventory
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  locked_inventory public.inventory;
  locked_product_id uuid;
  product_state public.product_status;
  normalized_note text := nullif(btrim(p_note), '');
  next_quantity integer;
  manager_or_owner boolean := public.is_manager_or_owner();
begin
  if auth.uid() is null or not public.is_staff_or_above() then
    raise exception 'Inventory operation permission required' using errcode = '42501';
  end if;
  if p_quantity_delta = 0 then raise exception 'Inventory movement quantity must be nonzero' using errcode = '23514'; end if;
  if p_movement_type not in ('stock_added', 'manual_adjustment', 'waste') then raise exception 'This movement type is reserved for a trusted operation' using errcode = '42501'; end if;
  if p_movement_type = 'stock_added' and p_quantity_delta < 0 then raise exception 'Stock-added movements must increase quantity' using errcode = '23514'; end if;
  if p_movement_type = 'waste' and p_quantity_delta > 0 then raise exception 'Waste movements must decrease quantity' using errcode = '23514'; end if;
  if p_movement_type in ('waste', 'manual_adjustment') and normalized_note is null then raise exception 'A note is required for this movement type' using errcode = '23514'; end if;

  select p.id, p.status into locked_product_id, product_state
  from public.products p
  where p.id = (select i.product_id from public.inventory i where i.id = p_inventory_id)
  for share;
  if not found then raise exception 'Inventory record or product not found' using errcode = '23503'; end if;

  select * into locked_inventory from public.inventory where id = p_inventory_id for update;
  if not found or locked_inventory.product_id <> locked_product_id then raise exception 'Inventory record not found' using errcode = '23503'; end if;
  if not locked_inventory.is_tracking_enabled then raise exception 'Inventory tracking is disabled for this product' using errcode = '23514'; end if;
  if not manager_or_owner and (p_movement_type not in ('stock_added', 'waste') or product_state <> 'active'::public.product_status) then raise exception 'Staff may only add stock or record waste for active products' using errcode = '42501'; end if;

  next_quantity := locked_inventory.quantity_on_hand + p_quantity_delta;
  if next_quantity < locked_inventory.quantity_reserved then raise exception 'Inventory quantity cannot fall below reserved quantity' using errcode = '23514'; end if;
  update public.inventory set quantity_on_hand = next_quantity where id = locked_inventory.id returning * into locked_inventory;
  insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, note, actor_user_id)
  values (locked_inventory.id, locked_inventory.product_id, p_movement_type, p_quantity_delta, locked_inventory.quantity_on_hand - p_quantity_delta, locked_inventory.quantity_on_hand, 0, locked_inventory.quantity_reserved, locked_inventory.quantity_reserved, normalized_note, auth.uid());
  return locked_inventory;
end;
$$;

create or replace function public.prevent_order_item_or_history_mutation()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  raise exception 'Order snapshots and status history are immutable' using errcode = '42501';
end;
$$;
create trigger order_items_immutable_before_mutation before update or delete on public.order_items for each row execute function public.prevent_order_item_or_history_mutation();
create trigger order_status_history_immutable_before_mutation before update or delete on public.order_status_history for each row execute function public.prevent_order_item_or_history_mutation();

create or replace function public.protect_order_snapshot()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.id is distinct from old.id or new.order_number is distinct from old.order_number or new.idempotency_key is distinct from old.idempotency_key
    or new.request_fingerprint is distinct from old.request_fingerprint or new.customer_name is distinct from old.customer_name
    or new.customer_email is distinct from old.customer_email or new.customer_phone is distinct from old.customer_phone
    or new.delivery_address is distinct from old.delivery_address or new.postcode_snapshot is distinct from old.postcode_snapshot
    or new.delivery_zone_id is distinct from old.delivery_zone_id or new.delivery_zone_name_snapshot is distinct from old.delivery_zone_name_snapshot
    or new.subtotal is distinct from old.subtotal or new.delivery_fee is distinct from old.delivery_fee
    or new.discount_amount is distinct from old.discount_amount or new.tax_amount is distinct from old.tax_amount
    or new.tax_label_snapshot is distinct from old.tax_label_snapshot or new.tax_rate_percent_snapshot is distinct from old.tax_rate_percent_snapshot
    or new.total is distinct from old.total or new.currency_code is distinct from old.currency_code
    or new.customer_note is distinct from old.customer_note or new.reservation_expires_at is distinct from old.reservation_expires_at then
    raise exception 'Order financial and customer snapshots are immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger orders_protect_snapshot_before_update before update on public.orders for each row execute function public.protect_order_snapshot();

-- The expiry path follows the existing-order lock order: order, products, then inventory.
create or replace function public.expire_pending_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  locked_order public.orders;
  locked_inventory public.inventory;
  order_line record;
begin
  select * into locked_order from public.orders where id = p_order_id for update;
  if not found or locked_order.status <> 'pending_payment' or locked_order.reservation_expires_at > now() then return; end if;

  perform 1 from public.products p join public.order_items oi on oi.product_id = p.id
  where oi.order_id = locked_order.id order by p.id for share;

  for locked_inventory in
    select i.* from public.inventory i join public.order_items oi on oi.product_id = i.product_id
    where oi.order_id = locked_order.id and i.is_tracking_enabled order by i.product_id for update
  loop
    select quantity into order_line from public.order_items where order_id = locked_order.id and product_id = locked_inventory.product_id;
    update public.inventory set quantity_reserved = quantity_reserved - order_line.quantity where id = locked_inventory.id returning * into locked_inventory;
    insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
    values (locked_inventory.id, locked_inventory.product_id, 'order_release', 0, locked_inventory.quantity_on_hand, locked_inventory.quantity_on_hand, -order_line.quantity, locked_inventory.quantity_reserved + order_line.quantity, locked_inventory.quantity_reserved, locked_order.id, 'order', locked_order.id);
  end loop;
  update public.orders set status = 'cancelled', updated_at = now() where id = locked_order.id;
  insert into public.order_status_history (order_id, previous_status, new_status, reason) values (locked_order.id, 'pending_payment', 'cancelled', 'payment_timeout');
end;
$$;

-- Phase 5 overrides keep existing configuration in product -> inventory lock order
-- and prohibit disabling tracking while that row still carries reservations.
create or replace function public.configure_product_inventory(
  p_product_id uuid,
  p_is_tracking_enabled boolean,
  p_low_stock_threshold integer
)
returns public.inventory
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  configured_inventory public.inventory;
  existing_inventory public.inventory;
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Inventory configuration permission required' using errcode = '42501';
  end if;
  if p_low_stock_threshold is not null and p_low_stock_threshold < 0 then
    raise exception 'Low-stock threshold cannot be negative' using errcode = '23514';
  end if;
  perform 1 from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found' using errcode = '23503'; end if;
  select * into existing_inventory from public.inventory where product_id = p_product_id for update;
  if found and not p_is_tracking_enabled and existing_inventory.quantity_reserved > 0 then
    raise exception 'Inventory tracking cannot be disabled while stock is reserved' using errcode = '23514';
  end if;
  insert into public.inventory (product_id, is_tracking_enabled, low_stock_threshold)
  values (p_product_id, p_is_tracking_enabled, p_low_stock_threshold)
  on conflict (product_id) do update set
    is_tracking_enabled = excluded.is_tracking_enabled,
    low_stock_threshold = excluded.low_stock_threshold
  returning * into configured_inventory;
  return configured_inventory;
end;
$$;

create or replace function public.create_guest_order(p_payload jsonb)
returns table(order_id uuid, order_number text, subtotal numeric, delivery_fee numeric, discount_amount numeric, tax_amount numeric, total numeric, currency_code char(3), status public.order_status, reservation_expires_at timestamptz)
language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_key uuid := (p_payload->>'idempotency_key')::uuid;
  v_lines jsonb := p_payload->'lines';
  v_fingerprint text;
  v_order public.orders;
  v_zone record;
  v_rechecked_zone record;
  v_check_zone record;
  v_normalized_postcode text := public.normalize_postcode(p_payload->>'postcode');
  v_settings public.business_settings;
  v_subtotal numeric(10,2);
  v_product record;
  v_line record;
  v_inventory public.inventory;
begin
  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) not between 1 and 20 then raise exception 'invalid_cart' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_key::text, 5));
  v_fingerprint := md5(jsonb_build_object('lines', (select jsonb_agg(jsonb_build_object('product_id', product_id, 'quantity', quantity) order by product_id) from (select (value->>'product_id')::uuid product_id, sum((value->>'quantity')::integer) quantity from jsonb_array_elements(v_lines) group by 1) normalized), 'name', btrim(p_payload->>'customer_name'), 'email', lower(btrim(p_payload->>'customer_email')), 'phone', btrim(p_payload->>'customer_phone'), 'address', btrim(p_payload->>'delivery_address'), 'postcode', v_normalized_postcode, 'note', nullif(btrim(p_payload->>'customer_note'),''))::text);
  select * into v_order from public.orders where idempotency_key = v_key;
  if found then
    if v_order.request_fingerprint <> v_fingerprint then raise exception 'idempotency_conflict' using errcode='22023'; end if;
    if v_order.status <> 'pending_payment' then raise exception 'expired_idempotency_key' using errcode='23514'; end if;
    return query select v_order.id,v_order.order_number,v_order.subtotal,v_order.delivery_fee,v_order.discount_amount,v_order.tax_amount,v_order.total,v_order.currency_code,v_order.status,v_order.reservation_expires_at;
    return;
  end if;
  if char_length(btrim(p_payload->>'customer_name')) not between 2 and 100 or char_length(btrim(p_payload->>'customer_email')) not between 3 and 254 or char_length(btrim(p_payload->>'customer_phone')) not between 7 and 32 or char_length(btrim(p_payload->>'delivery_address')) not between 6 and 500 or char_length(coalesce(p_payload->>'customer_note','')) > 500 then raise exception 'invalid_customer_details' using errcode='22023'; end if;
  create temporary table if not exists checkout_lines(product_id uuid primary key, quantity integer not null check(quantity between 1 and 99)) on commit drop;
  truncate checkout_lines;
  insert into checkout_lines select (value->>'product_id')::uuid, sum((value->>'quantity')::integer) from jsonb_array_elements(v_lines) group by 1;
  if exists(select 1 from checkout_lines where quantity not between 1 and 99) then raise exception 'invalid_quantity' using errcode='22023'; end if;
  for v_product in select p.* from public.products p join checkout_lines l on l.product_id=p.id order by p.id for share loop
    if v_product.status <> 'active' or not v_product.is_available or v_product.price_on_request or v_product.base_price is null then raise exception 'product_unavailable' using errcode='23514'; end if;
  end loop;
  if (select count(*) from checkout_lines) <> (select count(*) from public.products p join checkout_lines l on l.product_id=p.id) then raise exception 'product_not_found' using errcode='23503'; end if;
  select round(sum(l.quantity * coalesce(p.sale_price,p.base_price)),2) into v_subtotal from checkout_lines l join public.products p on p.id=l.product_id;

  -- Lock/re-read the selected delivery row. A committed manager change before
  -- the lock is acquired is used; a later change waits behind this checkout.
  loop
    select * into v_zone from public.resolve_active_delivery_zone(p_payload->>'postcode');
    if not found then raise exception 'unsupported_delivery_area' using errcode='23514'; end if;
    select z.id as zone_id, z.name as zone_name, z.delivery_fee, z.minimum_order, v_normalized_postcode as normalized_postcode
      into v_rechecked_zone
    from public.delivery_zones z cross join lateral unnest(z.postcode_prefixes) prefix(value)
    where z.id = v_zone.zone_id and z.is_active and v_normalized_postcode like prefix.value || '%'
    limit 1 for share of z;
    if not found then continue; end if;
    select * into v_check_zone from public.resolve_active_delivery_zone(p_payload->>'postcode');
    if found and v_check_zone.zone_id = v_rechecked_zone.zone_id then
      v_zone := v_rechecked_zone;
      exit;
    end if;
  end loop;
  select * into v_settings from public.business_settings where id=1 for share;
  if v_settings.tax_enabled then raise exception 'tax_configuration_required' using errcode='23514'; end if;
  if v_zone.minimum_order is not null and v_subtotal < v_zone.minimum_order then raise exception 'minimum_order_not_met' using errcode='23514'; end if;
  for v_inventory in select i.* from public.inventory i join checkout_lines l on l.product_id=i.product_id where i.is_tracking_enabled order by i.product_id for update loop
    select * into v_line from checkout_lines where product_id=v_inventory.product_id;
    if v_inventory.quantity_on_hand - v_inventory.quantity_reserved < v_line.quantity then raise exception 'insufficient_stock' using errcode='23514'; end if;
  end loop;
  insert into public.orders(order_number,idempotency_key,request_fingerprint,status,customer_name,customer_email,customer_phone,delivery_address,postcode_snapshot,delivery_zone_id,delivery_zone_name_snapshot,subtotal,delivery_fee,tax_amount,total,customer_note,reservation_expires_at)
  values ('SYF-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),v_key,v_fingerprint,'pending_payment',btrim(p_payload->>'customer_name'),lower(btrim(p_payload->>'customer_email')),btrim(p_payload->>'customer_phone'),btrim(p_payload->>'delivery_address'),v_zone.normalized_postcode,v_zone.zone_id,v_zone.zone_name,v_subtotal,v_zone.delivery_fee,0,v_subtotal+v_zone.delivery_fee,nullif(btrim(p_payload->>'customer_note'),''),now()+interval '15 minutes') returning * into v_order;
  insert into public.order_items(order_id,product_id,product_slug_snapshot,product_name_snapshot,portion_note_snapshot,quantity,unit_price,line_subtotal) select v_order.id,p.id,p.slug,p.name,p.portion_note,l.quantity,coalesce(p.sale_price,p.base_price),l.quantity*coalesce(p.sale_price,p.base_price) from checkout_lines l join public.products p on p.id=l.product_id;
  for v_inventory in select i.* from public.inventory i join checkout_lines l on l.product_id=i.product_id where i.is_tracking_enabled order by i.product_id for update loop
    select * into v_line from checkout_lines where product_id=v_inventory.product_id;
    update public.inventory set quantity_reserved=quantity_reserved+v_line.quantity where id=v_inventory.id returning * into v_inventory;
    insert into public.inventory_movements(inventory_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reserved_delta,reserved_before,reserved_after,order_id,reference_type,reference_id) values(v_inventory.id,v_inventory.product_id,'order_reservation',0,v_inventory.quantity_on_hand,v_inventory.quantity_on_hand,v_line.quantity,v_inventory.quantity_reserved-v_line.quantity,v_inventory.quantity_reserved,v_order.id,'order',v_order.id);
  end loop;
  insert into public.order_status_history(order_id,new_status) values(v_order.id,'pending_payment');
  return query select v_order.id,v_order.order_number,v_order.subtotal,v_order.delivery_fee,v_order.discount_amount,v_order.tax_amount,v_order.total,v_order.currency_code,v_order.status,v_order.reservation_expires_at;
end;
$$;

create or replace function public.expire_pending_order(p_order_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  locked_order public.orders;
  reservation record;
begin
  select * into locked_order from public.orders where id = p_order_id for update;
  if not found or locked_order.status <> 'pending_payment' or locked_order.reservation_expires_at > now() then return; end if;
  perform 1 from public.products p join (
    select product_id from public.inventory_movements where order_id = locked_order.id and movement_type in ('order_reservation','order_release','order_deduction') group by product_id having sum(reserved_delta) > 0
  ) outstanding on outstanding.product_id = p.id order by p.id for share of p;
  for reservation in
    select i.id as inventory_id, i.product_id, i.quantity_on_hand, i.quantity_reserved, outstanding.reserved_quantity
    from public.inventory i join (
      select inventory_id, product_id, sum(reserved_delta) as reserved_quantity
      from public.inventory_movements where order_id = locked_order.id and movement_type in ('order_reservation','order_release','order_deduction')
      group by inventory_id, product_id having sum(reserved_delta) > 0
    ) outstanding on outstanding.inventory_id = i.id and outstanding.product_id = i.product_id
    order by i.product_id for update of i
  loop
    if reservation.quantity_reserved < reservation.reserved_quantity then raise exception 'Inventory reservation ledger is inconsistent for expired order' using errcode = '23514'; end if;
    update public.inventory set quantity_reserved = quantity_reserved - reservation.reserved_quantity where id = reservation.inventory_id returning quantity_reserved into reservation.quantity_reserved;
    insert into public.inventory_movements (inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
    values (reservation.inventory_id, reservation.product_id, 'order_release', 0, reservation.quantity_on_hand, reservation.quantity_on_hand, -reservation.reserved_quantity, reservation.quantity_reserved + reservation.reserved_quantity, reservation.quantity_reserved, locked_order.id, 'order', locked_order.id);
  end loop;
  update public.orders set status = 'cancelled', updated_at = now() where id = locked_order.id;
  insert into public.order_status_history(order_id, previous_status, new_status, reason) values(locked_order.id, 'pending_payment', 'cancelled', 'payment_timeout');
end;
$$;

revoke all on function public.expire_pending_order(uuid) from public;
revoke all on function public.expire_pending_order(uuid) from anon;
revoke all on function public.expire_pending_order(uuid) from authenticated;
grant execute on function public.expire_pending_order(uuid) to service_role;
