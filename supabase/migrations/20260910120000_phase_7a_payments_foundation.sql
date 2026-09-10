  -- Phase 7A: payment-attempt foundation and trusted payment lifecycle RPCs.

  create type public.payment_provider as enum ('stripe');
  create type public.payment_status as enum (
    'awaiting_payment_intent',
    'payment_intent_attached',
    'payment_failed',
    'succeeded',
    'late_success_requires_reconciliation'
  );
  create type public.payment_provider_event_outcome as enum (
    'processed',
    'duplicate',
    'rejected',
    'late_success_requires_reconciliation',
    'payment_failed'
  );

  create table public.payments (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete restrict,
    provider public.payment_provider not null default 'stripe',
    status public.payment_status not null default 'awaiting_payment_intent',
    amount_minor bigint not null check (amount_minor > 0),
    currency_code char(3) not null check (currency_code = 'GBP'),
    attempt_sequence integer not null default 1 check (attempt_sequence > 0),
    provider_idempotency_key uuid not null default gen_random_uuid() unique,
    payment_capability_hash text check (payment_capability_hash is null or payment_capability_hash ~ '^[0-9a-f]{64}$'),
    provider_payment_intent_id text unique check (provider_payment_intent_id is null or char_length(btrim(provider_payment_intent_id)) between 1 and 255),
    provider_charge_id text unique check (provider_charge_id is null or char_length(btrim(provider_charge_id)) between 1 and 255),
    provider_failure_code text check (provider_failure_code is null or provider_failure_code ~ '^[A-Za-z0-9_]{1,100}$'),
    provider_succeeded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (order_id, attempt_sequence)
  );

  create unique index payments_one_active_attempt_per_order_idx
    on public.payments (order_id)
    where status in ('awaiting_payment_intent', 'payment_intent_attached', 'payment_failed');
  create index payments_order_created_at_idx on public.payments (order_id, created_at desc);

  create table public.payment_provider_events (
    id uuid primary key default gen_random_uuid(),
    provider public.payment_provider not null default 'stripe',
    provider_event_id text not null check (char_length(btrim(provider_event_id)) between 1 and 255),
    event_type text not null check (char_length(btrim(event_type)) between 1 and 120),
    payment_id uuid references public.payments(id) on delete restrict,
    order_id uuid references public.orders(id) on delete restrict,
    provider_object_id text not null check (char_length(btrim(provider_object_id)) between 1 and 255),
    provider_created_at timestamptz,
    received_at timestamptz not null default now(),
    processed_at timestamptz,
    processing_outcome public.payment_provider_event_outcome,
    payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
    processing_error_code text check (processing_error_code is null or processing_error_code ~ '^[A-Za-z0-9_]{1,100}$'),
    unique (provider, provider_event_id)
  );

  create index payment_provider_events_payment_received_at_idx
    on public.payment_provider_events (payment_id, received_at desc);
  create index payment_provider_events_order_received_at_idx
    on public.payment_provider_events (order_id, received_at desc);

  create trigger payments_set_updated_at_before_update
  before update on public.payments
  for each row execute function public.set_updated_at();

  alter table public.audit_logs drop constraint audit_logs_entity_type_check;
  alter table public.audit_logs add constraint audit_logs_entity_type_check
    check (entity_type in ('category', 'product', 'product_image', 'business_settings', 'delivery_zone', 'inventory', 'order', 'payment'));

  -- Phase 7B will supply this SHA-256 hash from the Edge Function. Keeping it
  -- nullable temporarily preserves Phase 5 checkout during the staggered deploy;
  -- a legacy row without a hash can never be prepared for payment below.
  create or replace function public.create_guest_order(p_payload jsonb)
  returns table(order_id uuid, order_number text, subtotal numeric, delivery_fee numeric, discount_amount numeric, tax_amount numeric, total numeric, currency_code char(3), status public.order_status, reservation_expires_at timestamptz)
  language plpgsql
  security definer
  set search_path = pg_catalog, public
  as $$
  declare
    v_key uuid := (p_payload->>'idempotency_key')::uuid;
    v_lines jsonb := p_payload->'lines';
    v_fingerprint text;
    v_capability_hash text := nullif(lower(btrim(p_payload->>'payment_capability_hash')), '');
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
    if v_capability_hash is not null and v_capability_hash !~ '^[0-9a-f]{64}$' then
      raise exception 'invalid_payment_session' using errcode = '22023';
    end if;
    if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) not between 1 and 20 then raise exception 'invalid_cart' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended(v_key::text, 5));
    v_fingerprint := md5(jsonb_build_object('lines', (select jsonb_agg(jsonb_build_object('product_id', product_id, 'quantity', quantity) order by product_id) from (select (value->>'product_id')::uuid product_id, sum((value->>'quantity')::integer) quantity from jsonb_array_elements(v_lines) group by 1) normalized), 'name', btrim(p_payload->>'customer_name'), 'email', lower(btrim(p_payload->>'customer_email')), 'phone', btrim(p_payload->>'customer_phone'), 'address', btrim(p_payload->>'delivery_address'), 'postcode', v_normalized_postcode, 'note', nullif(btrim(p_payload->>'customer_note'),''))::text);
    select * into v_order from public.orders where idempotency_key = v_key;
    if found then
      if v_order.request_fingerprint <> v_fingerprint then raise exception 'idempotency_conflict' using errcode='22023'; end if;
      if v_order.status <> 'pending_payment' then raise exception 'expired_idempotency_key' using errcode='23514'; end if;
      -- Orders created before Phase 7A have no payment row. They may complete the
      -- original no-capability idempotent retry only; a later capability can never
      -- claim or bind that historical order.
      if not exists (
        select 1 from public.payments payment
        where payment.order_id = v_order.id
          and payment.attempt_sequence = 1
      ) then
        if v_capability_hash is not null then
          raise exception 'invalid_payment_session' using errcode = '22023';
        end if;
      elsif not exists (
        select 1 from public.payments payment
        where payment.order_id = v_order.id
          and payment.attempt_sequence = 1
          and payment.payment_capability_hash is not distinct from v_capability_hash
      ) then
        raise exception 'invalid_payment_session' using errcode = '22023';
      end if;
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
      if found and v_check_zone.zone_id = v_rechecked_zone.zone_id then v_zone := v_rechecked_zone; exit; end if;
    end loop;
    select * into v_settings from public.business_settings where id=1 for share;
    if v_settings.tax_enabled then raise exception 'tax_configuration_required' using errcode='23514'; end if;
    if v_zone.minimum_order is not null and v_subtotal < v_zone.minimum_order then raise exception 'minimum_order_not_met' using errcode='23514'; end if;
    if v_subtotal + v_zone.delivery_fee <= 0 then raise exception 'payment_amount_invalid' using errcode = '23514'; end if;
    for v_inventory in select i.* from public.inventory i join checkout_lines l on l.product_id=i.product_id where i.is_tracking_enabled order by i.product_id for update loop
      select * into v_line from checkout_lines where product_id=v_inventory.product_id;
      if v_inventory.quantity_on_hand - v_inventory.quantity_reserved < v_line.quantity then raise exception 'insufficient_stock' using errcode='23514'; end if;
    end loop;
    insert into public.orders(order_number,idempotency_key,request_fingerprint,status,customer_name,customer_email,customer_phone,delivery_address,postcode_snapshot,delivery_zone_id,delivery_zone_name_snapshot,subtotal,delivery_fee,tax_amount,total,customer_note,reservation_expires_at)
    values ('SYF-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),v_key,v_fingerprint,'pending_payment',btrim(p_payload->>'customer_name'),lower(btrim(p_payload->>'customer_email')),btrim(p_payload->>'customer_phone'),btrim(p_payload->>'delivery_address'),v_zone.normalized_postcode,v_zone.zone_id,v_zone.zone_name,v_subtotal,v_zone.delivery_fee,0,v_subtotal+v_zone.delivery_fee,nullif(btrim(p_payload->>'customer_note'),''),now()+interval '15 minutes') returning * into v_order;
    insert into public.payments(order_id, provider, status, amount_minor, currency_code, attempt_sequence, payment_capability_hash)
    values (v_order.id, 'stripe', 'awaiting_payment_intent', (v_order.total * 100)::bigint, v_order.currency_code, 1, v_capability_hash);
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

  create or replace function public.prepare_stripe_payment_attempt(
    p_order_id uuid,
    p_payment_capability_hash text
  )
  returns table (
    payment_id uuid,
    order_id uuid,
    amount_minor bigint,
    currency_code char(3),
    provider_idempotency_key uuid,
    provider_payment_intent_id text
  )
  language plpgsql
  security definer
  set search_path = pg_catalog, public
  as $$
  declare
    locked_order public.orders;
    locked_payment public.payments;
  begin
    if p_payment_capability_hash !~ '^[0-9a-f]{64}$' then raise exception 'payment_session_unavailable' using errcode = '22023'; end if;
    select * into locked_order from public.orders where id = p_order_id for update;
    if not found or locked_order.status <> 'pending_payment' or locked_order.reservation_expires_at <= now() or locked_order.total <= 0 or locked_order.currency_code <> 'GBP' then
      raise exception 'payment_session_unavailable' using errcode = '22023';
    end if;
    select * into locked_payment from public.payments payment
    where payment.order_id = locked_order.id
      and provider = 'stripe'
      and payment_capability_hash = p_payment_capability_hash
    order by attempt_sequence desc
    limit 1
    for update;
    if not found or locked_payment.status not in ('awaiting_payment_intent', 'payment_intent_attached', 'payment_failed') then
      raise exception 'payment_session_unavailable' using errcode = '22023';
    end if;
    if locked_payment.amount_minor <> (locked_order.total * 100)::bigint or locked_payment.currency_code <> locked_order.currency_code then
      raise exception 'Payment attempt does not match order total' using errcode = '23514';
    end if;
    return query select locked_payment.id, locked_order.id, locked_payment.amount_minor, locked_payment.currency_code, locked_payment.provider_idempotency_key, locked_payment.provider_payment_intent_id;
  end;
  $$;

  create or replace function public.attach_stripe_payment_intent(
    p_payment_id uuid,
    p_expected_provider_payment_intent_id text,
    p_provider_payment_intent_id text
  )
  returns table (
    payment_id uuid,
    order_id uuid,
    provider_payment_intent_id text,
    status public.payment_status
  )
  language plpgsql
  security definer
  set search_path = pg_catalog, public
  as $$
  declare
    locked_payment public.payments;
  begin
    if nullif(btrim(p_provider_payment_intent_id), '') is null or char_length(btrim(p_provider_payment_intent_id)) > 255 then
      raise exception 'Invalid provider payment intent identity' using errcode = '22023';
    end if;
    select * into locked_payment from public.payments where id = p_payment_id for update;
    if not found or locked_payment.provider <> 'stripe' then raise exception 'Payment attempt not found' using errcode = '23503'; end if;
    if locked_payment.provider_payment_intent_id is distinct from nullif(btrim(p_expected_provider_payment_intent_id), '') then
      raise exception 'Payment attempt has changed; refresh and try again' using errcode = '40001';
    end if;
    if locked_payment.provider_payment_intent_id is not null and locked_payment.provider_payment_intent_id <> btrim(p_provider_payment_intent_id) then
      raise exception 'Conflicting provider payment intent identity' using errcode = '23514';
    end if;
    if locked_payment.status not in ('awaiting_payment_intent', 'payment_intent_attached', 'payment_failed') then
      raise exception 'Payment attempt is not attachable' using errcode = '23514';
    end if;
    return query
    update public.payments as payment
    set provider_payment_intent_id = btrim(p_provider_payment_intent_id),
        status = case when locked_payment.status = 'awaiting_payment_intent' then 'payment_intent_attached'::public.payment_status else locked_payment.status end,
        provider_failure_code = case when locked_payment.status = 'payment_failed' then null else payment.provider_failure_code end
    where payment.id = locked_payment.id
    returning payment.id, payment.order_id, payment.provider_payment_intent_id, payment.status;
  end;
  $$;

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
    insert into public.payment_provider_events(provider, provider_event_id, event_type, provider_object_id, provider_created_at, payload_sha256)
    values ('stripe', btrim(p_provider_event_id), 'payment_intent.succeeded', btrim(p_provider_payment_intent_id), p_provider_created_at, p_payload_sha256)
    on conflict (provider, provider_event_id) do nothing
    returning id into inserted_event_id;
    if inserted_event_id is null then
      return query select 'duplicate', p_payment_id, p_order_id;
      return;
    end if;

    select * into locked_order from public.orders where id = p_order_id for update;
    if not found then
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch' where id = inserted_event_id;
      return query select 'rejected', p_payment_id, p_order_id;
      return;
    end if;
    select * into locked_payment from public.payments where id = p_payment_id for update;
    if not found or locked_order.id <> locked_payment.order_id or locked_payment.provider <> 'stripe' or locked_payment.provider_payment_intent_id <> btrim(p_provider_payment_intent_id) or locked_payment.amount_minor <> p_verified_amount_minor or normalized_currency <> 'GBP' or locked_payment.currency_code <> 'GBP' or (locked_payment.provider_charge_id is not null and nullif(btrim(p_provider_charge_id), '') is not null and locked_payment.provider_charge_id <> btrim(p_provider_charge_id)) then
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch' where id = inserted_event_id;
      return query select 'rejected', p_payment_id, p_order_id;
      return;
    end if;
    update public.payment_provider_events set payment_id = locked_payment.id, order_id = locked_order.id where id = inserted_event_id;
    if locked_payment.status = 'succeeded' and locked_order.status = 'confirmed' then
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'duplicate' where id = inserted_event_id;
      return query select 'duplicate', locked_payment.id, locked_order.id;
      return;
    end if;
    -- A normal verified success can only consume an open payment attempt. This
    -- is an expected reconciliation failure, so retain the provider event rather
    -- than raising and rolling its deduplication record back.
    if locked_order.status = 'pending_payment'
      and locked_payment.status not in ('awaiting_payment_intent', 'payment_intent_attached', 'payment_failed') then
      update public.payment_provider_events
      set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_state_invalid'
      where id = inserted_event_id;
      return query select 'rejected', locked_payment.id, locked_order.id;
      return;
    end if;
    if locked_order.status = 'pending_payment' and locked_order.reservation_expires_at <= now() then
      perform public.expire_pending_order(locked_order.id);
      select * into locked_order from public.orders where id = p_order_id for update;
    end if;
    if locked_order.status <> 'pending_payment' then
      update public.payments
      set status = 'late_success_requires_reconciliation', provider_charge_id = coalesce(nullif(btrim(p_provider_charge_id), ''), provider_charge_id), provider_succeeded_at = coalesce(p_provider_created_at, now()), provider_failure_code = null
      where id = locked_payment.id;
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'late_success_requires_reconciliation' where id = inserted_event_id;
      insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, old_values, new_values)
      values (null, 'update', 'payment', locked_payment.id, jsonb_build_object('status', locked_payment.status), jsonb_build_object('status', 'late_success_requires_reconciliation', 'provider', 'stripe'));
      return query select 'late_success_requires_reconciliation', locked_payment.id, locked_order.id;
      return;
    end if;

    perform 1
    from public.products product_row
    join (
      select product_id from public.inventory_movements
      where order_id = locked_order.id and movement_type in ('order_reservation', 'order_release', 'order_deduction')
      group by product_id having sum(reserved_delta) > 0
    ) outstanding on outstanding.product_id = product_row.id
    order by product_row.id
    for share of product_row;
    -- Preflight every locked reservation before mutating any balance. Expected
    -- ledger inconsistencies are durably rejected with no partial deduction;
    -- unexpected database failures still abort and remain retryable.
    for reservation in
      select inventory_row.id as inventory_id, inventory_row.product_id, inventory_row.quantity_on_hand, inventory_row.quantity_reserved, outstanding.reserved_quantity
      from public.inventory inventory_row
      join (
        select inventory_id, product_id, sum(reserved_delta) as reserved_quantity
        from public.inventory_movements
        where order_id = locked_order.id and movement_type in ('order_reservation', 'order_release', 'order_deduction')
        group by inventory_id, product_id having sum(reserved_delta) > 0
      ) outstanding on outstanding.inventory_id = inventory_row.id and outstanding.product_id = inventory_row.product_id
      order by inventory_row.product_id
      for update of inventory_row
    loop
      if reservation.quantity_reserved < reservation.reserved_quantity or reservation.quantity_on_hand < reservation.reserved_quantity then
        update public.payment_provider_events
        set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'inventory_ledger_inconsistent'
        where id = inserted_event_id;
        return query select 'rejected', locked_payment.id, locked_order.id;
        return;
      end if;
    end loop;

    for reservation in
      select inventory_row.id as inventory_id, inventory_row.product_id, inventory_row.quantity_on_hand, inventory_row.quantity_reserved, outstanding.reserved_quantity
      from public.inventory inventory_row
      join (
        select inventory_id, product_id, sum(reserved_delta) as reserved_quantity
        from public.inventory_movements
        where order_id = locked_order.id and movement_type in ('order_reservation', 'order_release', 'order_deduction')
        group by inventory_id, product_id having sum(reserved_delta) > 0
      ) outstanding on outstanding.inventory_id = inventory_row.id and outstanding.product_id = inventory_row.product_id
      order by inventory_row.product_id
      for update of inventory_row
    loop
      update public.inventory
      set quantity_on_hand = quantity_on_hand - reservation.reserved_quantity,
          quantity_reserved = quantity_reserved - reservation.reserved_quantity
      where id = reservation.inventory_id;
      insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
      values (reservation.inventory_id, reservation.product_id, 'order_deduction', -reservation.reserved_quantity, reservation.quantity_on_hand, reservation.quantity_on_hand - reservation.reserved_quantity, -reservation.reserved_quantity, reservation.quantity_reserved, reservation.quantity_reserved - reservation.reserved_quantity, locked_order.id, 'order', locked_order.id);
    end loop;
    update public.payments
    set status = 'succeeded', provider_charge_id = coalesce(nullif(btrim(p_provider_charge_id), ''), provider_charge_id), provider_succeeded_at = coalesce(p_provider_created_at, now()), provider_failure_code = null
    where id = locked_payment.id;
    update public.orders set status = 'confirmed', updated_at = now() where id = locked_order.id;
    insert into public.order_status_history(order_id, previous_status, new_status, actor_user_id, reason)
    values (locked_order.id, 'pending_payment', 'confirmed', null, 'stripe_payment_succeeded');
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, old_values, new_values)
    values (null, 'update', 'order', locked_order.id, jsonb_build_object('status', 'pending_payment'), jsonb_build_object('status', 'confirmed', 'payment_provider', 'stripe'));
    update public.payment_provider_events set processed_at = now(), processing_outcome = 'processed' where id = inserted_event_id;
    return query select 'processed', locked_payment.id, locked_order.id;
  end;
  $$;

  create or replace function public.record_verified_stripe_payment_failure(
    p_provider_event_id text,
    p_provider_payment_intent_id text,
    p_payment_id uuid,
    p_order_id uuid,
    p_provider_created_at timestamptz,
    p_failure_code text,
    p_payload_sha256 text
  )
  returns text
  language plpgsql
  security definer
  set search_path = pg_catalog, public
  as $$
  declare
    inserted_event_id uuid;
    locked_payment public.payments;
    locked_order public.orders;
  begin
    if nullif(btrim(p_provider_event_id), '') is null or nullif(btrim(p_provider_payment_intent_id), '') is null or nullif(btrim(p_failure_code), '') is null or btrim(p_failure_code) !~ '^[A-Za-z0-9_]{1,100}$' or p_payload_sha256 !~ '^[0-9a-f]{64}$' then
      raise exception 'Invalid verified Stripe payment failure input' using errcode = '22023';
    end if;
    insert into public.payment_provider_events(provider, provider_event_id, event_type, provider_object_id, provider_created_at, payload_sha256)
    values ('stripe', btrim(p_provider_event_id), 'payment_intent.payment_failed', btrim(p_provider_payment_intent_id), p_provider_created_at, p_payload_sha256)
    on conflict (provider, provider_event_id) do nothing
    returning id into inserted_event_id;
    if inserted_event_id is null then return 'duplicate'; end if;
    select * into locked_order from public.orders where id = p_order_id for update;
    if not found then
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch' where id = inserted_event_id;
      return 'rejected';
    end if;
    select * into locked_payment from public.payments where id = p_payment_id for update;
    if not found or locked_order.id <> locked_payment.order_id or locked_payment.provider <> 'stripe' or locked_payment.provider_payment_intent_id <> btrim(p_provider_payment_intent_id) then
      update public.payment_provider_events set processed_at = now(), processing_outcome = 'rejected', processing_error_code = 'payment_binding_mismatch' where id = inserted_event_id;
      return 'rejected';
    end if;
    update public.payment_provider_events set payment_id = locked_payment.id, order_id = locked_order.id, processed_at = now(), processing_outcome = 'payment_failed', processing_error_code = btrim(p_failure_code) where id = inserted_event_id;
    if locked_order.status = 'pending_payment' and locked_payment.status not in ('succeeded', 'late_success_requires_reconciliation') then
      update public.payments set status = 'payment_failed', provider_failure_code = btrim(p_failure_code) where id = locked_payment.id;
    end if;
    return 'payment_failed';
  end;
  $$;

  alter table public.payments enable row level security;
  alter table public.payment_provider_events enable row level security;
  revoke all on table public.payments, public.payment_provider_events from anon, authenticated;
  grant select (id, order_id, provider, status, amount_minor, currency_code, attempt_sequence, provider_payment_intent_id, provider_charge_id, provider_failure_code, provider_succeeded_at, created_at, updated_at) on table public.payments to authenticated;
  grant select on table public.payment_provider_events to authenticated;
  create policy "payments_manager_owner_read"
  on public.payments for select to authenticated
  using (public.is_manager_or_owner());
  create policy "payment_provider_events_owner_read"
  on public.payment_provider_events for select to authenticated
  using (public.is_owner());

  revoke all on function public.prepare_stripe_payment_attempt(uuid, text) from public, anon, authenticated;
  revoke all on function public.attach_stripe_payment_intent(uuid, text, text) from public, anon, authenticated;
  revoke all on function public.process_verified_stripe_payment_success(text, text, text, uuid, uuid, bigint, text, timestamptz, text) from public, anon, authenticated;
  revoke all on function public.record_verified_stripe_payment_failure(text, text, uuid, uuid, timestamptz, text, text) from public, anon, authenticated;
  grant execute on function public.prepare_stripe_payment_attempt(uuid, text) to service_role;
  grant execute on function public.attach_stripe_payment_intent(uuid, text, text) to service_role;
  grant execute on function public.process_verified_stripe_payment_success(text, text, text, uuid, uuid, bigint, text, timestamptz, text) to service_role;
  grant execute on function public.record_verified_stripe_payment_failure(text, text, uuid, uuid, timestamptz, text, text) to service_role;
