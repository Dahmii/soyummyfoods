-- Phase 10C verification. Run after Phases 1-10C in a disposable database.
-- Fixture identities, orders, payment attempts, and audit-visible rows roll back.

begin;

do $$
declare
  v_result text;
begin
  if has_function_privilege('anon', 'public.get_admin_order_payment_summary(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'public.get_admin_order_payment_summary(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.get_admin_order_payment_summary(uuid)', 'EXECUTE') then
    raise exception 'Operational payment-summary RPC grants are incorrect';
  end if;

  select lower(pg_get_function_result('public.get_admin_order_payment_summary(uuid)'::regprocedure)) into v_result;
  if v_result not like '%order_id uuid%'
     or (v_result not like '%payment_status public.payment_status%' and v_result not like '%payment_status payment_status%')
     or v_result not like '%amount_minor bigint%'
     or (v_result not like '%currency_code character(3)%' and v_result not like '%currency_code character%')
     or (v_result not like '%provider public.payment_provider%' and v_result not like '%provider payment_provider%')
     or v_result not like '%paid_at timestamp with time zone%'
     or v_result not like '%requires_manager_review boolean%'
     or v_result like '%payment_id%'
     or v_result like '%attempt_sequence%'
     or v_result like '%payment_intent%'
     or v_result like '%charge%'
     or v_result like '%capability%'
     or v_result like '%failure%'
     or v_result like '%reconciliation_note%'
     or v_result like '%resolved_by%' then
    raise exception 'Operational payment-summary DTO is too broad or incomplete';
  end if;

  if not exists (
    select 1
    from pg_proc as procedure_row
    where procedure_row.oid = 'public.get_admin_order_payment_summary(uuid)'::regprocedure
      and procedure_row.prosecdef
      and procedure_row.provolatile = 's'
      and exists (
        select 1
        from unnest(coalesce(procedure_row.proconfig, array[]::text[])) as setting_row(value)
        where setting_row.value = 'search_path=pg_catalog, public'
      )
  ) then raise exception 'Operational payment-summary execution boundary is unsafe'; end if;
end;
$$;

do $$
declare
  v_owner uuid := '00000000-0000-4000-8000-0000000010c1'::uuid;
  v_manager uuid := '00000000-0000-4000-8000-0000000010c2'::uuid;
  v_staff uuid := '00000000-0000-4000-8000-0000000010c3'::uuid;
  v_unrelated uuid := '00000000-0000-4000-8000-0000000010c4'::uuid;
  v_normal_order uuid := '00000000-0000-4000-8000-0000000010c5'::uuid;
  v_failed_order uuid := '00000000-0000-4000-8000-0000000010c6'::uuid;
  v_retry_order uuid := '00000000-0000-4000-8000-0000000010c7'::uuid;
  v_late_order uuid := '00000000-0000-4000-8000-0000000010c8'::uuid;
  v_no_payment_order uuid := '00000000-0000-4000-8000-0000000010c9'::uuid;
begin
  if exists (
    select 1 from auth.users as auth_user
    where auth_user.id in (v_owner, v_manager, v_staff, v_unrelated)
       or auth_user.email in ('phase-10c-owner@example.test', 'phase-10c-manager@example.test', 'phase-10c-staff@example.test', 'phase-10c-unrelated@example.test')
  ) or exists (
    select 1 from public.profiles as profile_row
    where profile_row.id in (v_owner, v_manager, v_staff, v_unrelated)
  ) then
    raise exception 'Phase 10C reserved fixture identities already exist';
  end if;

  insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (v_owner, 'authenticated', 'authenticated', 'phase-10c-owner@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_manager, 'authenticated', 'authenticated', 'phase-10c-manager@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_staff, 'authenticated', 'authenticated', 'phase-10c-staff@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
    (v_unrelated, 'authenticated', 'authenticated', 'phase-10c-unrelated@example.test', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

  if (select count(*) from public.profiles where id in (v_owner, v_manager, v_staff, v_unrelated)) <> 4 then
    raise exception 'Auth fixture creation did not invoke the profile trigger';
  end if;
  insert into public.user_roles (user_id, role) values (v_owner, 'owner'), (v_manager, 'manager'), (v_staff, 'staff');

  insert into public.orders (id, order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values
    (v_normal_order, 'SYF-20260918-10C00001', gen_random_uuid(), 'phase-10c-normal', 'confirmed', 'Phase 10C Customer', 'phase10c-normal@example.test', '1234567', '10 Test Street', 'P10CTEST', 'Phase 10C zone', 15.49, 0, 0, 0, 15.49, 'GBP', now() - interval '1 hour'),
    (v_failed_order, 'SYF-20260918-10C00002', gen_random_uuid(), 'phase-10c-failed', 'pending_payment', 'Phase 10C Customer', 'phase10c-failed@example.test', '1234567', '10 Test Street', 'P10CTEST', 'Phase 10C zone', 10, 0, 0, 0, 10, 'GBP', now() + interval '10 minutes'),
    (v_retry_order, 'SYF-20260918-10C00003', gen_random_uuid(), 'phase-10c-retry', 'confirmed', 'Phase 10C Customer', 'phase10c-retry@example.test', '1234567', '10 Test Street', 'P10CTEST', 'Phase 10C zone', 12, 0, 0, 0, 12, 'GBP', now() - interval '1 hour'),
    (v_late_order, 'SYF-20260918-10C00004', gen_random_uuid(), 'phase-10c-late', 'cancelled', 'Phase 10C Customer', 'phase10c-late@example.test', '1234567', '10 Test Street', 'P10CTEST', 'Phase 10C zone', 9, 0, 0, 0, 9, 'GBP', now() - interval '1 hour'),
    (v_no_payment_order, 'SYF-20260918-10C00005', gen_random_uuid(), 'phase-10c-none', 'pending_payment', 'Phase 10C Customer', 'phase10c-none@example.test', '1234567', '10 Test Street', 'P10CTEST', 'Phase 10C zone', 8, 0, 0, 0, 8, 'GBP', now() + interval '10 minutes');

  insert into public.payments (order_id, attempt_sequence, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values
    (v_normal_order, 1, 'succeeded', 1549, 'GBP', repeat('a', 64), 'pi_phase10c_normal', 'ch_phase10c_normal', '2026-09-18 10:17:00+00'),
    (v_failed_order, 1, 'payment_failed', 1000, 'GBP', repeat('b', 64), 'pi_phase10c_failed', null, null),
    (v_retry_order, 1, 'payment_failed', 1200, 'GBP', repeat('c', 64), 'pi_phase10c_retry_failed', null, null),
    (v_retry_order, 2, 'succeeded', 1200, 'GBP', repeat('d', 64), 'pi_phase10c_retry_paid', 'ch_phase10c_retry_paid', '2026-09-18 10:18:00+00'),
    (v_late_order, 1, 'late_success_requires_reconciliation', 900, 'GBP', repeat('e', 64), 'pi_phase10c_late', 'ch_phase10c_late', '2026-09-18 10:19:00+00');
end;
$$;

set local role anon;
do $$
begin
  begin perform public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c5'); raise exception 'Anon executed the payment summary'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c4', true);
do $$
begin
  begin perform public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c5'); raise exception 'Unrelated authenticated user read a payment summary'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c3', true);
do $$
declare
  v_normal record;
  v_failed record;
  v_retry record;
  v_late record;
begin
  if exists (select 1 from public.payments where order_id in ('00000000-0000-4000-8000-0000000010c5'::uuid, '00000000-0000-4000-8000-0000000010c6'::uuid)) then
    raise exception 'Staff directly read payments rows';
  end if;
  select * into v_normal from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c5');
  if not found or v_normal.payment_status <> 'succeeded'::public.payment_status or v_normal.amount_minor <> 1549 or v_normal.currency_code <> 'GBP' or v_normal.provider <> 'stripe'::public.payment_provider or v_normal.paid_at <> '2026-09-18 10:17:00+00'::timestamptz or v_normal.requires_manager_review then
    raise exception 'Staff did not receive the narrow normal paid summary';
  end if;
  select * into v_failed from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c6');
  if not found or v_failed.payment_status <> 'payment_failed'::public.payment_status or v_failed.paid_at is not null or v_failed.requires_manager_review then
    raise exception 'Failed attempt summary is incorrect';
  end if;
  select * into v_retry from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c7');
  if not found or v_retry.payment_status <> 'succeeded'::public.payment_status or v_retry.amount_minor <> 1200 then
    raise exception 'Successful retry did not take precedence over a failed attempt';
  end if;
  select * into v_late from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c8');
  if not found or v_late.payment_status <> 'late_success_requires_reconciliation'::public.payment_status or not v_late.requires_manager_review or v_late.paid_at is null then
    raise exception 'Late success was normalized or did not require review';
  end if;
  if exists (select 1 from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c9')) then
    raise exception 'Order without a payment attempt returned a fabricated summary';
  end if;
end;
$$;

reset role;
do $$
begin
  update public.payments
  set reconciliation_resolved_at = now(),
      reconciliation_resolved_by = '00000000-0000-4000-8000-0000000010c1'::uuid,
      reconciliation_resolution_code = 'other'
  where order_id = '00000000-0000-4000-8000-0000000010c8'::uuid;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c3', true);
do $$
declare v_late record;
begin
  select * into v_late from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c8');
  if not found
     or v_late.payment_status <> 'late_success_requires_reconciliation'::public.payment_status
     or v_late.requires_manager_review then
    raise exception 'Resolved late success did not remain exceptional with review recorded';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c2', true);
do $$
begin
  if not exists (select 1 from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c5')) then raise exception 'Manager could not read the payment summary'; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000010c1', true);
do $$
begin
  if not exists (select 1 from public.get_admin_order_payment_summary('00000000-0000-4000-8000-0000000010c5')) then raise exception 'Owner could not read the payment summary'; end if;
end;
$$;

reset role;
rollback;
