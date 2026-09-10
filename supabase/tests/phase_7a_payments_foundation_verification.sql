-- Phase 7A verification. Run after Phases 1-7A in a disposable database only.
-- Replace OWNER_AUTH_USER_UUID / MANAGER_AUTH_USER_UUID / STAFF_AUTH_USER_UUID
-- with real auth.users IDs. Every fixture and mutation is rolled back.

begin;

create temporary table phase_7a_ids (key text primary key, value uuid not null) on commit drop;
grant select, insert, update, delete on table phase_7a_ids to authenticated, service_role;

-- This transaction-only trigger creates an initially expired order snapshot for
-- late-success coverage without mutating immutable production order snapshots.
create function public.phase_7a_test_set_expired_reservation()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.idempotency_key = '70000000-0000-4000-8000-000000000002'::uuid then
    new.reservation_expires_at = now() - interval '1 second';
  end if;
  return new;
end;
$$;
create trigger phase_7a_test_set_expired_reservation_before_insert
before insert on public.orders
for each row execute function public.phase_7a_test_set_expired_reservation();

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'payments') then raise exception 'payments table missing'; end if;
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'payment_provider_events') then raise exception 'payment_provider_events table missing'; end if;
  if has_function_privilege('anon', 'public.prepare_stripe_payment_attempt(uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.prepare_stripe_payment_attempt(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.attach_stripe_payment_intent(uuid,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.attach_stripe_payment_intent(uuid,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.process_verified_stripe_payment_success(text,text,text,uuid,uuid,bigint,text,timestamptz,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.process_verified_stripe_payment_success(text,text,text,uuid,uuid,bigint,text,timestamptz,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.record_verified_stripe_payment_failure(text,text,uuid,uuid,timestamptz,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.record_verified_stripe_payment_failure(text,text,uuid,uuid,timestamptz,text,text)', 'EXECUTE') then
    raise exception 'A browser role can execute a trusted Phase 7A payment RPC';
  end if;
  if not has_function_privilege('service_role', 'public.prepare_stripe_payment_attempt(uuid,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.attach_stripe_payment_intent(uuid,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.process_verified_stripe_payment_success(text,text,text,uuid,uuid,bigint,text,timestamptz,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.record_verified_stripe_payment_failure(text,text,uuid,uuid,timestamptz,text,text)', 'EXECUTE') then
    raise exception 'Trusted Phase 7A RPC grants are missing';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin perform 1 from public.payments; raise exception 'Anon read payments'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.payment_provider_events; raise exception 'Anon read provider events'; exception when insufficient_privilege then null; end;
  begin insert into public.payments(order_id, amount_minor, currency_code) values ('00000000-0000-0000-0000-000000000000', 1, 'GBP'); raise exception 'Anon inserted payment'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
declare v_category_id uuid; v_product_id uuid; v_zero_product_id uuid; v_inventory_id uuid; v_zone_id uuid;
begin
  select id into v_category_id from public.categories order by display_order limit 1;
  if v_category_id is null then raise exception 'A seeded category is required'; end if;
  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values(v_category_id, 'phase-7a-payment-test', 'Phase 7A payment test', 'Disposable payment verification product.', 10, 1, 'draft', true, 99980)
  returning id into v_product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order) values(v_product_id, '/phase-7a-test.jpg', true, 0);
  update public.products set status = 'active' where id = v_product_id;
  select id into v_inventory_id from public.configure_product_inventory(v_product_id, true, null);
  perform public.adjust_inventory(v_inventory_id, 'stock_added', 10, null);
  insert into public.delivery_zones(name, is_active, postcode_prefixes, delivery_fee, minimum_order, match_priority, display_order)
  values('Phase 7A zone', true, array['P7TEST'], 2, null, 0, 99980) returning id into v_zone_id;
  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values(v_category_id, 'phase-7a-zero-test', 'Phase 7A zero test', 'Disposable zero-total verification product.', 0, 1, 'draft', true, 99981)
  returning id into v_zero_product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order) values(v_zero_product_id, '/phase-7a-zero.jpg', true, 0);
  update public.products set status = 'active' where id = v_zero_product_id;
  insert into public.delivery_zones(name, is_active, postcode_prefixes, delivery_fee, minimum_order, match_priority, display_order)
  values('Phase 7A zero zone', true, array['P7ZERO'], 0, null, 0, 99981);
  insert into phase_7a_ids values ('product', v_product_id), ('inventory', v_inventory_id), ('zero_product', v_zero_product_id), ('zone', v_zone_id);
end;
$$;

reset role;
set local role service_role;
do $$
declare
  v_product_id uuid := (select value from phase_7a_ids where key = 'product');
  v_zero_product_id uuid := (select value from phase_7a_ids where key = 'zero_product');
  created record;
  retried record;
  v_order_id uuid;
  v_legacy_order_id uuid;
  v_late_order_id uuid;
  v_rejected_order_id uuid;
  v_payment_id uuid;
  v_late_payment_id uuid;
  v_rejected_payment_id uuid;
  prepared record;
  payload jsonb;
  legacy_payload jsonb;
  legacy_fingerprint text;
  capability_hash text := repeat('a', 64);
  late_capability_hash text := repeat('b', 64);
  rejected_capability_hash text := repeat('9', 64);
begin
  payload := jsonb_build_object('idempotency_key', '70000000-0000-4000-8000-000000000001', 'payment_capability_hash', capability_hash, 'lines', jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 2)), 'customer_name', 'Phase Seven', 'customer_email', 'phase7@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P7 TEST', 'customer_note', null);
  select * into created from public.create_guest_order(payload);
  v_order_id := created.order_id;
  if created.total <> 22 or created.currency_code <> 'GBP' or created.status <> 'pending_payment' then raise exception 'Authoritative payment order snapshot failed'; end if;
  select payment.id into v_payment_id from public.payments payment where payment.order_id = v_order_id;
  if v_payment_id is null or (select count(*) from public.payments payment where payment.order_id = v_order_id) <> 1 then raise exception 'Checkout did not create exactly one payment row'; end if;
  if (select amount_minor from public.payments where id = v_payment_id) <> 2200 or (select payment_capability_hash from public.payments where id = v_payment_id) <> capability_hash then raise exception 'Payment amount/capability snapshot failed'; end if;
  select * into retried from public.create_guest_order(payload);
  if retried.order_id <> v_order_id or (select count(*) from public.payments payment where payment.order_id = v_order_id) <> 1 or (select count(*) from public.inventory_movements movement where movement.order_id = v_order_id and movement.movement_type = 'order_reservation') <> 1 then raise exception 'Checkout retry duplicated payment, order, or reservation'; end if;
  begin perform public.create_guest_order(payload || jsonb_build_object('payment_capability_hash', repeat('c', 64))); raise exception 'Mismatched capability was accepted'; exception when invalid_parameter_value then null; end;
  -- This is the hash-backed order's own live retry. Once it is confirmed below,
  -- its idempotency key must instead remain terminal and raise expired_idempotency_key.
  begin perform public.create_guest_order(payload - 'payment_capability_hash'); raise exception 'Hash-backed payment accepted a null retry capability'; exception when invalid_parameter_value then null; end;
  begin perform public.create_guest_order(jsonb_build_object('idempotency_key', '70000000-0000-4000-8000-000000000003', 'payment_capability_hash', repeat('d', 64), 'lines', jsonb_build_array(jsonb_build_object('product_id', v_zero_product_id, 'quantity', 1)), 'customer_name', 'Zero Total', 'customer_email', 'zero@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P7 ZERO', 'customer_note', null)); raise exception 'Zero-total checkout was accepted'; exception when check_violation then null; end;
  select * into prepared from public.prepare_stripe_payment_attempt(v_order_id, capability_hash);
  if prepared.payment_id <> v_payment_id or prepared.amount_minor <> 2200 or prepared.currency_code <> 'GBP' or prepared.provider_idempotency_key is null or prepared.provider_payment_intent_id is not null then raise exception 'Payment preparation returned invalid trusted data'; end if;
  if (select provider_idempotency_key from public.prepare_stripe_payment_attempt(v_order_id, capability_hash)) <> prepared.provider_idempotency_key then raise exception 'Payment preparation identity changed across retries'; end if;
  begin perform public.prepare_stripe_payment_attempt(v_order_id, repeat('e', 64)); raise exception 'Wrong payment capability prepared an attempt'; exception when invalid_parameter_value then null; end;
  perform public.attach_stripe_payment_intent(v_payment_id, null, 'pi_phase7a_success');
  perform public.attach_stripe_payment_intent(v_payment_id, 'pi_phase7a_success', 'pi_phase7a_success');
  begin perform public.attach_stripe_payment_intent(v_payment_id, 'pi_phase7a_success', 'pi_phase7a_conflict'); raise exception 'Conflicting provider identity accepted'; exception when check_violation then null; end;
  if public.record_verified_stripe_payment_failure('evt_phase7a_failure', 'pi_phase7a_success', v_payment_id, v_order_id, now(), 'card_declined', repeat('6', 64)) <> 'payment_failed' then raise exception 'Verified payment failure was not recorded'; end if;
  if (select status from public.payments where id = v_payment_id) <> 'payment_failed' then raise exception 'Verified payment failure did not update the attempt state'; end if;
  if public.record_verified_stripe_payment_failure('evt_phase7a_failure', 'pi_phase7a_success', v_payment_id, v_order_id, now(), 'card_declined', repeat('6', 64)) <> 'duplicate' then raise exception 'Duplicate payment failure was not harmless'; end if;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_amount', 'pi_phase7a_success', 'ch_phase7a_success', v_payment_id, v_order_id, 2199, 'GBP', now(), repeat('1', 64))) <> 'rejected' then raise exception 'Amount mismatch was not rejected'; end if;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_currency', 'pi_phase7a_success', 'ch_phase7a_success', v_payment_id, v_order_id, 2200, 'USD', now(), repeat('2', 64))) <> 'rejected' then raise exception 'Currency mismatch was not rejected'; end if;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_success', 'pi_phase7a_success', 'ch_phase7a_success', v_payment_id, v_order_id, 2200, 'GBP', now(), repeat('3', 64))) <> 'processed' then raise exception 'Verified success was not processed'; end if;
  if (select status from public.orders where id = v_order_id) <> 'confirmed' or (select status from public.payments where id = v_payment_id) <> 'succeeded' then raise exception 'Payment success did not confirm order/payment'; end if;
  if (select quantity_on_hand from public.inventory where id = (select value from phase_7a_ids where key = 'inventory')) <> 8 or (select quantity_reserved from public.inventory where id = (select value from phase_7a_ids where key = 'inventory')) <> 0 then raise exception 'Payment success did not deduct on-hand/reserved inventory exactly'; end if;
  if (select count(*) from public.inventory_movements movement where movement.order_id = v_order_id and movement.movement_type = 'order_deduction' and movement.quantity_delta = -2 and movement.reserved_delta = -2) <> 1 then raise exception 'Payment success did not write one correct deduction'; end if;
  if not exists (select 1 from public.order_status_history history where history.order_id = v_order_id and history.previous_status = 'pending_payment' and history.new_status = 'confirmed' and history.actor_user_id is null) then raise exception 'Payment confirmation history missing'; end if;
  if not exists (select 1 from public.audit_logs audit where audit.entity_type = 'order' and audit.entity_id = v_order_id and audit.action = 'update' and audit.actor_user_id is null and audit.old_values = jsonb_build_object('status', 'pending_payment') and audit.new_values = jsonb_build_object('status', 'confirmed', 'payment_provider', 'stripe')) then raise exception 'Payment confirmation audit missing'; end if;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_success', 'pi_phase7a_success', 'ch_phase7a_success', v_payment_id, v_order_id, 2200, 'GBP', now(), repeat('3', 64))) <> 'duplicate' then raise exception 'Duplicate provider event was not harmless'; end if;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_repeat', 'pi_phase7a_success', 'ch_phase7a_success', v_payment_id, v_order_id, 2200, 'GBP', now(), repeat('4', 64))) <> 'duplicate' then raise exception 'Repeated PaymentIntent success was not harmless'; end if;
  if (select count(*) from public.inventory_movements movement where movement.order_id = v_order_id and movement.movement_type = 'order_deduction') <> 1 then raise exception 'Repeated success double-deducted inventory'; end if;

  -- Simulate an order created by Phase 5 before the payments table existed.
  -- Its exact no-capability retry remains idempotent, but it is permanently
  -- legacy/non-payable through the new Stripe preparation path.
  legacy_payload := jsonb_build_object('idempotency_key', '70000000-0000-4000-8000-000000000004', 'lines', jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 1)), 'customer_name', 'Legacy Seven', 'customer_email', 'legacy@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P7 TEST', 'customer_note', null);
  legacy_fingerprint := md5(jsonb_build_object('lines', (select jsonb_agg(jsonb_build_object('product_id', normalized.product_id, 'quantity', normalized.quantity) order by normalized.product_id) from (select (line_item.value->>'product_id')::uuid as product_id, sum((line_item.value->>'quantity')::integer) as quantity from jsonb_array_elements(legacy_payload->'lines') line_item(value) group by 1) normalized), 'name', btrim(legacy_payload->>'customer_name'), 'email', lower(btrim(legacy_payload->>'customer_email')), 'phone', btrim(legacy_payload->>'customer_phone'), 'address', btrim(legacy_payload->>'delivery_address'), 'postcode', public.normalize_postcode(legacy_payload->>'postcode'), 'note', nullif(btrim(legacy_payload->>'customer_note'), ''))::text);
  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_id, delivery_zone_name_snapshot, subtotal, delivery_fee, tax_amount, total, reservation_expires_at)
  values ('SYF-20260910-AAAAAA04', '70000000-0000-4000-8000-000000000004', legacy_fingerprint, 'pending_payment', 'Legacy Seven', 'legacy@example.test', '1234567', '10 Test Street', 'P7TEST', (select value from phase_7a_ids where key = 'zone'), 'Phase 7A zone', 10, 2, 0, 12, now() + interval '15 minutes')
  returning id into v_legacy_order_id;
  insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, quantity, unit_price, line_subtotal)
  values (v_legacy_order_id, v_product_id, 'phase-7a-payment-test', 'Phase 7A payment test', 1, 10, 10);
  update public.inventory set quantity_reserved = quantity_reserved + 1 where id = (select value from phase_7a_ids where key = 'inventory');
  insert into public.inventory_movements(inventory_id, product_id, movement_type, quantity_delta, quantity_before, quantity_after, reserved_delta, reserved_before, reserved_after, order_id, reference_type, reference_id)
  values ((select value from phase_7a_ids where key = 'inventory'), v_product_id, 'order_reservation', 0, 8, 8, 1, 0, 1, v_legacy_order_id, 'order', v_legacy_order_id);
  select * into retried from public.create_guest_order(legacy_payload);
  if retried.order_id <> v_legacy_order_id or exists (select 1 from public.payments payment where payment.order_id = v_legacy_order_id) or (select count(*) from public.inventory_movements movement where movement.order_id = v_legacy_order_id and movement.movement_type = 'order_reservation') <> 1 then raise exception 'Pre-7A no-payment retry was not preserved safely'; end if;
  begin perform public.create_guest_order(legacy_payload || jsonb_build_object('payment_capability_hash', repeat('f', 64))); raise exception 'Legacy null capability was claimable'; exception when invalid_parameter_value then null; end;
  begin perform public.prepare_stripe_payment_attempt(v_legacy_order_id, null); raise exception 'Legacy/null payment was prepared'; exception when invalid_parameter_value then null; end;

  payload := jsonb_build_object('idempotency_key', '70000000-0000-4000-8000-000000000002', 'payment_capability_hash', late_capability_hash, 'lines', jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 1)), 'customer_name', 'Late Seven', 'customer_email', 'late@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P7 TEST', 'customer_note', null);
  select * into created from public.create_guest_order(payload);
  v_late_order_id := created.order_id;
  select payment.id into v_late_payment_id from public.payments payment where payment.order_id = v_late_order_id;
  begin perform public.prepare_stripe_payment_attempt(v_late_order_id, late_capability_hash); raise exception 'Expired order prepared a payment'; exception when invalid_parameter_value then null; end;
  perform public.attach_stripe_payment_intent(v_late_payment_id, null, 'pi_phase7a_late');
  perform public.expire_pending_order(v_late_order_id);
  begin perform public.prepare_stripe_payment_attempt(v_late_order_id, late_capability_hash); raise exception 'Cancelled order prepared a payment'; exception when invalid_parameter_value then null; end;
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_late', 'pi_phase7a_late', 'ch_phase7a_late', v_late_payment_id, v_late_order_id, 1200, 'GBP', now(), repeat('5', 64))) <> 'late_success_requires_reconciliation' then raise exception 'Late success was not retained for reconciliation'; end if;
  if (select status from public.orders where id = v_late_order_id) <> 'cancelled' or (select status from public.payments where id = v_late_payment_id) <> 'late_success_requires_reconciliation' then raise exception 'Late success revived order or did not persist reconciliation state'; end if;
  if (select count(*) from public.inventory_movements movement where movement.order_id = v_late_order_id and movement.movement_type = 'order_deduction') <> 0 then raise exception 'Late success deducted inventory'; end if;
  if not exists (select 1 from public.audit_logs audit where audit.entity_type = 'payment' and audit.entity_id = v_late_payment_id and audit.action = 'update' and audit.actor_user_id is null and audit.old_values = jsonb_build_object('status', 'payment_intent_attached') and audit.new_values = jsonb_build_object('status', 'late_success_requires_reconciliation', 'provider', 'stripe')) then raise exception 'Late-success payment audit missing'; end if;
  begin perform public.prepare_stripe_payment_attempt(v_order_id, capability_hash); raise exception 'Terminal payment prepared again'; exception when invalid_parameter_value then null; end;

  -- An expected ledger inconsistency is durably rejected before any deduction.
  payload := jsonb_build_object('idempotency_key', '70000000-0000-4000-8000-000000000005', 'payment_capability_hash', rejected_capability_hash, 'lines', jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 2)), 'customer_name', 'Rejected Seven', 'customer_email', 'rejected@example.test', 'customer_phone', '1234567', 'delivery_address', '10 Test Street', 'postcode', 'P7 TEST', 'customer_note', null);
  select * into created from public.create_guest_order(payload);
  v_rejected_order_id := created.order_id;
  select payment.id into v_rejected_payment_id from public.payments payment where payment.order_id = v_rejected_order_id;
  perform public.attach_stripe_payment_intent(v_rejected_payment_id, null, 'pi_phase7a_rejected');
  -- Deliberately corrupt only this disposable fixture's aggregate balance. The
  -- authoritative ledger still demands two reserved portions for this order.
  update public.inventory set quantity_reserved = 1 where id = (select value from phase_7a_ids where key = 'inventory');
  if (select outcome from public.process_verified_stripe_payment_success('evt_phase7a_rejected', 'pi_phase7a_rejected', 'ch_phase7a_rejected', v_rejected_payment_id, v_rejected_order_id, 2200, 'GBP', now(), repeat('0', 64))) <> 'rejected' then raise exception 'Ledger inconsistency was not durably rejected'; end if;
  if (select status from public.orders where id = v_rejected_order_id) <> 'pending_payment' or (select status from public.payments where id = v_rejected_payment_id) <> 'payment_intent_attached' or (select count(*) from public.inventory_movements movement where movement.order_id = v_rejected_order_id and movement.movement_type = 'order_deduction') <> 0 then raise exception 'Rejected ledger event made a partial business mutation'; end if;
  if not exists (select 1 from public.payment_provider_events where provider_event_id = 'evt_phase7a_rejected' and processing_outcome = 'rejected' and processing_error_code = 'inventory_ledger_inconsistent') then raise exception 'Rejected ledger event was not persisted'; end if;
  insert into phase_7a_ids values ('order', v_order_id), ('payment', v_payment_id);
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'MANAGER_AUTH_USER_UUID', true);
do $$
begin
  if not exists (select 1 from public.payments) then raise exception 'Manager could not read operational payment state'; end if;
  if exists (select 1 from public.payment_provider_events) then raise exception 'Manager read restricted provider events'; end if;
  begin perform payment_capability_hash from public.payments limit 1; raise exception 'Manager read payment capability hash'; exception when insufficient_privilege then null; end;
  begin perform provider_idempotency_key from public.payments limit 1; raise exception 'Manager read provider idempotency key'; exception when insufficient_privilege then null; end;
  begin insert into public.payments(order_id, amount_minor, currency_code) values ((select value from phase_7a_ids where key = 'order'), 1, 'GBP'); raise exception 'Manager inserted payment directly'; exception when insufficient_privilege then null; end;
  begin update public.payments set status = 'succeeded' where id = (select value from phase_7a_ids where key = 'payment'); raise exception 'Manager updated payment directly'; exception when insufficient_privilege then null; end;
  begin delete from public.payments where id = (select value from phase_7a_ids where key = 'payment'); raise exception 'Manager deleted payment directly'; exception when insufficient_privilege then null; end;
  begin insert into public.payment_provider_events(provider, provider_event_id, event_type, provider_object_id, payload_sha256) values ('stripe', 'evt_phase7a_manager', 'test', 'pi_phase7a_success', repeat('7', 64)); raise exception 'Manager inserted provider event directly'; exception when insufficient_privilege then null; end;
  begin update public.payment_provider_events set processing_outcome = 'processed'; raise exception 'Manager updated provider event directly'; exception when insufficient_privilege then null; end;
  begin delete from public.payment_provider_events; raise exception 'Manager deleted provider event directly'; exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub', 'OWNER_AUTH_USER_UUID', true);
do $$
begin
  if not exists (select 1 from public.payment_provider_events) then raise exception 'Owner could not read provider-event reconciliation records'; end if;
  begin perform payment_capability_hash from public.payments limit 1; raise exception 'Owner read payment capability hash'; exception when insufficient_privilege then null; end;
  begin perform provider_idempotency_key from public.payments limit 1; raise exception 'Owner read provider idempotency key'; exception when insufficient_privilege then null; end;
  begin insert into public.payments(order_id, amount_minor, currency_code) values ((select value from phase_7a_ids where key = 'order'), 1, 'GBP'); raise exception 'Owner inserted payment directly'; exception when insufficient_privilege then null; end;
  begin update public.payments set status = 'succeeded' where id = (select value from phase_7a_ids where key = 'payment'); raise exception 'Owner updated payment directly'; exception when insufficient_privilege then null; end;
  begin delete from public.payments where id = (select value from phase_7a_ids where key = 'payment'); raise exception 'Owner deleted payment directly'; exception when insufficient_privilege then null; end;
  begin insert into public.payment_provider_events(provider, provider_event_id, event_type, provider_object_id, payload_sha256) values ('stripe', 'evt_phase7a_owner', 'test', 'pi_phase7a_success', repeat('8', 64)); raise exception 'Owner inserted provider event directly'; exception when insufficient_privilege then null; end;
  begin update public.payment_provider_events set processing_outcome = 'processed'; raise exception 'Owner updated provider event directly'; exception when insufficient_privilege then null; end;
  begin delete from public.payment_provider_events; raise exception 'Owner deleted provider event directly'; exception when insufficient_privilege then null; end;
end;
$$;

select set_config('request.jwt.claim.sub', 'STAFF_AUTH_USER_UUID', true);
do $$
begin
  if exists (select 1 from public.payments) then raise exception 'Staff read unnecessary payment internals'; end if;
  if exists (select 1 from public.payment_provider_events) then raise exception 'Staff read provider events'; end if;
  begin insert into public.payments(order_id, amount_minor, currency_code) values ((select value from phase_7a_ids where key = 'order'), 1, 'GBP'); raise exception 'Staff inserted payment'; exception when insufficient_privilege then null; end;
  begin update public.payments set status = 'succeeded' where id = (select value from phase_7a_ids where key = 'payment'); raise exception 'Staff updated payment'; exception when insufficient_privilege then null; end;
  begin delete from public.payment_provider_events; raise exception 'Staff deleted provider event'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
do $$
begin
  if has_column_privilege('authenticated', 'public.payments', 'payment_capability_hash', 'SELECT')
     or has_column_privilege('authenticated', 'public.payments', 'provider_idempotency_key', 'SELECT') then
    raise exception 'Authenticated browser role received a sensitive payment column grant';
  end if;
end;
$$;
rollback;
