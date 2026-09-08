-- Phase 4: sellable-portion inventory and an immutable stock movement ledger.

create table public.inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null unique references public.products(id) on delete restrict,
  is_tracking_enabled boolean not null default false,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  low_stock_threshold integer check (low_stock_threshold is null or low_stock_threshold >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  unique (id, product_id)
);

create index inventory_tracking_quantity_idx
  on public.inventory (is_tracking_enabled, quantity_on_hand);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  inventory_id uuid not null,
  product_id uuid not null,
  movement_type text not null check (movement_type in (
    'stock_added', 'manual_adjustment', 'waste', 'order_deduction', 'order_restock'
  )),
  quantity_delta integer not null check (quantity_delta <> 0),
  quantity_before integer not null check (quantity_before >= 0),
  quantity_after integer not null check (quantity_after >= 0),
  note text,
  actor_user_id uuid references public.profiles(id) on delete set null,
  reference_type text,
  reference_id uuid,
  created_at timestamptz not null default now(),
  constraint inventory_movements_product_fk
    foreign key (product_id) references public.products(id) on delete restrict,
  constraint inventory_movements_inventory_product_fk
    foreign key (inventory_id, product_id) references public.inventory(id, product_id) on delete restrict,
  constraint inventory_movements_quantity_math check (quantity_after = quantity_before + quantity_delta),
  constraint inventory_movements_reference_pair check (
    (reference_type is null and reference_id is null)
    or (nullif(btrim(reference_type), '') is not null and reference_id is not null)
  ),
  constraint inventory_movements_required_note check (
    movement_type not in ('waste', 'manual_adjustment') or nullif(btrim(note), '') is not null
  )
);

create index inventory_movements_inventory_created_at_idx
  on public.inventory_movements (inventory_id, created_at desc);
create index inventory_movements_product_created_at_idx
  on public.inventory_movements (product_id, created_at desc);

create or replace function public.set_inventory_actor()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by = auth.uid();
    new.updated_by = auth.uid();
  else
    new.created_by = old.created_by;
    new.updated_by = auth.uid();
  end if;
  return new;
end;
$$;

create trigger inventory_set_actor_before_write
before insert or update on public.inventory
for each row execute function public.set_inventory_actor();

create trigger inventory_set_updated_at_before_update
before update on public.inventory
for each row execute function public.set_updated_at();

create or replace function public.prevent_inventory_movement_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  raise exception 'Inventory movements are immutable' using errcode = '42501';
end;
$$;

create trigger inventory_movements_immutable_before_mutation
before update or delete on public.inventory_movements
for each row execute function public.prevent_inventory_movement_mutation();

alter table public.audit_logs drop constraint audit_logs_entity_type_check;
alter table public.audit_logs add constraint audit_logs_entity_type_check
  check (entity_type in ('category', 'product', 'product_image', 'business_settings', 'delivery_zone', 'inventory'));

create or replace function public.write_inventory_configuration_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT'
     or new.is_tracking_enabled is distinct from old.is_tracking_enabled
     or new.low_stock_threshold is distinct from old.low_stock_threshold then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, old_values, new_values)
    values (
      auth.uid(), lower(tg_op), 'inventory', coalesce(new.id, old.id),
      case when tg_op = 'UPDATE' then to_jsonb(old) - 'quantity_on_hand' end,
      to_jsonb(new) - 'quantity_on_hand'
    );
  end if;
  return coalesce(new, old);
end;
$$;

create trigger inventory_write_configuration_audit_after_mutation
after insert or update on public.inventory
for each row execute function public.write_inventory_configuration_audit_log();

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
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Inventory configuration permission required' using errcode = '42501';
  end if;
  if p_low_stock_threshold is not null and p_low_stock_threshold < 0 then
    raise exception 'Low-stock threshold cannot be negative' using errcode = '23514';
  end if;

  -- Serializes first-time configuration for a product without creating rows for all products.
  perform 1 from public.products where id = p_product_id for update;
  if not found then raise exception 'Product not found' using errcode = '23503'; end if;

  insert into public.inventory (product_id, is_tracking_enabled, low_stock_threshold)
  values (p_product_id, p_is_tracking_enabled, p_low_stock_threshold)
  on conflict (product_id) do update set
    is_tracking_enabled = excluded.is_tracking_enabled,
    low_stock_threshold = excluded.low_stock_threshold
  returning * into configured_inventory;
  return configured_inventory;
end;
$$;

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
  if p_quantity_delta = 0 then
    raise exception 'Inventory movement quantity must be nonzero' using errcode = '23514';
  end if;
  if p_movement_type not in ('stock_added', 'manual_adjustment', 'waste') then
    raise exception 'This movement type is reserved for a trusted operation' using errcode = '42501';
  end if;
  if p_movement_type = 'stock_added' and p_quantity_delta < 0 then
    raise exception 'Stock-added movements must increase quantity' using errcode = '23514';
  end if;
  if p_movement_type = 'waste' and p_quantity_delta > 0 then
    raise exception 'Waste movements must decrease quantity' using errcode = '23514';
  end if;
  if p_movement_type in ('waste', 'manual_adjustment') and normalized_note is null then
    raise exception 'A note is required for this movement type' using errcode = '23514';
  end if;

  -- Lock product lifecycle first. FOR SHARE conflicts with product updates so a
  -- staff operation cannot act on an active status that is concurrently archived.
  select product_row.id, product_row.status
  into locked_product_id, product_state
  from public.products product_row
  where product_row.id = (
    select inventory_row.product_id
    from public.inventory inventory_row
    where inventory_row.id = p_inventory_id
  )
  for share;
  if not found then raise exception 'Inventory record or product not found' using errcode = '23503'; end if;

  -- Configuration and adjustment both acquire product then inventory locks.
  select inventory_row.*
  into locked_inventory
  from public.inventory inventory_row
  where inventory_row.id = p_inventory_id
  for update;
  if not found then raise exception 'Inventory record not found' using errcode = '23503'; end if;
  if locked_inventory.product_id <> locked_product_id then
    raise exception 'Inventory product relationship changed during adjustment' using errcode = '40001';
  end if;
  if not locked_inventory.is_tracking_enabled then
    raise exception 'Inventory tracking is disabled for this product' using errcode = '23514';
  end if;
  if not manager_or_owner then
    if p_movement_type not in ('stock_added', 'waste') or product_state <> 'active'::public.product_status then
      raise exception 'Staff may only add stock or record waste for active products' using errcode = '42501';
    end if;
  end if;

  next_quantity := locked_inventory.quantity_on_hand + p_quantity_delta;
  if next_quantity < 0 then raise exception 'Inventory quantity cannot become negative' using errcode = '23514'; end if;

  update public.inventory
  set quantity_on_hand = next_quantity
  where id = locked_inventory.id
  returning * into locked_inventory;

  insert into public.inventory_movements (
    inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, note, actor_user_id
  ) values (
    locked_inventory.id, locked_inventory.product_id, p_movement_type, p_quantity_delta,
    locked_inventory.quantity_on_hand - p_quantity_delta, locked_inventory.quantity_on_hand,
    normalized_note, auth.uid()
  );
  return locked_inventory;
end;
$$;

alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;
revoke all on table public.inventory from anon, authenticated;
revoke all on table public.inventory_movements from anon, authenticated;
grant select on table public.inventory to authenticated;
grant select on table public.inventory_movements to authenticated;

create policy "inventory_staff_read"
on public.inventory for select to authenticated
using (public.is_staff_or_above());
create policy "inventory_movements_staff_read"
on public.inventory_movements for select to authenticated
using (public.is_staff_or_above());

revoke all on function public.configure_product_inventory(uuid, boolean, integer) from public;
revoke all on function public.adjust_inventory(uuid, text, integer, text) from public;
grant execute on function public.configure_product_inventory(uuid, boolean, integer) to authenticated;
grant execute on function public.adjust_inventory(uuid, text, integer, text) to authenticated;

-- Phase 5 trusted multi-product order operations must lock inventory rows in a
-- deterministic inventory/product-ID order before validating and mutating stock.
