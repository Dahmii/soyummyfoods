-- Phase 9B verification. Run after Phases 1-9B in a disposable database only.
-- All fixtures below are transaction-local and rolled back.

begin;

do $$
declare
  v_result text;
begin
  if has_function_privilege('anon', 'public.get_guest_order_payment_status(uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.get_guest_order_payment_status(uuid,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.get_guest_order_payment_status(uuid,text)', 'EXECUTE') then
    raise exception 'Guest payment-status RPC grants are incorrect';
  end if;
  if has_table_privilege('anon', 'public.orders', 'SELECT')
     or has_table_privilege('anon', 'public.payments', 'SELECT') then
    raise exception 'Anon can directly read guest order/payment data';
  end if;

  select lower(pg_get_function_result('public.get_guest_order_payment_status(uuid,text)'::regprocedure))
    into v_result;
  if v_result not like '%order_id uuid%'
     or v_result not like '%order_number text%'
     or v_result not like '%order_status public.order_status%'
     or v_result not like '%payment_status public.payment_status%'
     or v_result not like '%terminal boolean%'
     or v_result not like '%subtotal numeric%'
     or v_result not like '%delivery_fee numeric%'
     or v_result not like '%discount_amount numeric%'
     or v_result not like '%tax_amount numeric%'
     or v_result not like '%total numeric%'
     or v_result not like '%currency_code character(3)%'
     or v_result not like '%reservation_expires_at timestamp with time zone%'
     or v_result like '%customer_%'
     or v_result like '%delivery_address%'
     or v_result like '%provider_%'
     or v_result like '%payment_capability%' then
    raise exception 'Guest payment-status DTO is not minimal or complete';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.get_guest_order_payment_status(gen_random_uuid(), repeat('a', 64));
    raise exception 'Anon executed guest payment-status RPC';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000009b9', true);
do $$
begin
  begin
    perform public.get_guest_order_payment_status(gen_random_uuid(), repeat('a', 64));
    raise exception 'Authenticated caller executed guest payment-status RPC';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role service_role;
do $$
declare
  v_target_order_id uuid := '00000000-0000-4000-8000-0000000009b1'::uuid;
  v_other_order_id uuid := '00000000-0000-4000-8000-0000000009b2'::uuid;
  v_target_capability_hash text := repeat('a', 64);
  v_other_capability_hash text := repeat('b', 64);
  v_result record;
begin
  insert into public.orders (
    id, order_number, idempotency_key, request_fingerprint, status,
    customer_name, customer_email, customer_phone, delivery_address,
    postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee,
    discount_amount, tax_amount, total, currency_code, reservation_expires_at
  ) values
    (v_target_order_id, 'SYF-20260913-9B000001', gen_random_uuid(), 'phase-9b-target', 'pending_payment', 'Phase 9B Customer', 'phase9b-target@example.test', '1234567', '10 Test Street', 'P9BTEST', 'Phase 9B zone', 12.50, 2.50, 1.00, 0.50, 14.50, 'GBP', now() + interval '10 minutes'),
    (v_other_order_id, 'SYF-20260913-9B000002', gen_random_uuid(), 'phase-9b-other', 'pending_payment', 'Other Customer', 'phase9b-other@example.test', '1234568', '11 Test Street', 'P9BTEST', 'Phase 9B zone', 10.00, 0, 0, 0, 10.00, 'GBP', now() + interval '10 minutes');

  insert into public.payments (order_id, attempt_sequence, status, amount_minor, currency_code, payment_capability_hash)
  values
    (v_target_order_id, 1, 'payment_intent_attached', 1450, 'GBP', v_target_capability_hash),
    (v_other_order_id, 1, 'payment_intent_attached', 1000, 'GBP', v_other_capability_hash);

  select * into v_result
  from public.get_guest_order_payment_status(v_target_order_id, v_target_capability_hash);
  if v_result.order_id <> v_target_order_id
     or v_result.order_number <> 'SYF-20260913-9B000001'
     or v_result.order_status <> 'pending_payment'::public.order_status
     or v_result.payment_status <> 'payment_intent_attached'::public.payment_status
     or v_result.terminal
     or v_result.subtotal <> 12.50
     or v_result.delivery_fee <> 2.50
     or v_result.discount_amount <> 1.00
     or v_result.tax_amount <> 0.50
     or v_result.total <> 14.50
     or v_result.currency_code <> 'GBP'
     or v_result.reservation_expires_at is null then
    raise exception 'Matching capability did not return authoritative financial status';
  end if;

  if exists (
    select 1 from public.get_guest_order_payment_status(v_target_order_id, v_other_capability_hash)
  ) then raise exception 'Another order capability read target order data'; end if;
  if exists (
    select 1 from public.get_guest_order_payment_status(v_other_order_id, v_target_capability_hash)
  ) then raise exception 'Target capability read another order data'; end if;
  if exists (
    select 1 from public.get_guest_order_payment_status(v_target_order_id, repeat('c', 64))
  ) then raise exception 'Wrong capability read target order data'; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000009b9', true);
do $$
declare
  v_target_order_id uuid := '00000000-0000-4000-8000-0000000009b1'::uuid;
begin
  if exists (select 1 from public.orders where id = v_target_order_id)
     or exists (select 1 from public.orders where order_number = 'SYF-20260913-9B000001')
     or exists (select 1 from public.payments where order_id = v_target_order_id) then
    raise exception 'Unaffiliated authenticated caller read guest data by ID or order number';
  end if;
end;
$$;

reset role;
rollback;
