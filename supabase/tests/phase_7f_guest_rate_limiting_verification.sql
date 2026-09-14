-- Phase 7F verification. Run after Phases 1-7F in a disposable database only.
-- Every row created below is rolled back.

begin;

do $$
begin
  if has_function_privilege('anon', 'public.consume_guest_rate_limit(text,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.consume_guest_rate_limit(text,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.purge_guest_rate_limit_windows()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.purge_guest_rate_limit_windows()', 'EXECUTE') then
    raise exception 'A browser role can execute a guest rate-limit function';
  end if;
  if not has_function_privilege('service_role', 'public.consume_guest_rate_limit(text,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.purge_guest_rate_limit_windows()', 'EXECUTE') then
    raise exception 'Service-role rate-limit function grants are missing';
  end if;
  if has_table_privilege('anon', 'private.guest_rate_limit_windows', 'SELECT')
     or has_table_privilege('authenticated', 'private.guest_rate_limit_windows', 'SELECT') then
    raise exception 'A browser role can read durable rate-limit state';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.consume_guest_rate_limit('guest-checkout', repeat('a', 64), repeat('b', 64));
    raise exception 'Anon executed the rate-limit consumer';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.purge_guest_rate_limit_windows();
    raise exception 'Anon executed the rate-limit purge';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
do $$
begin
  begin
    perform public.consume_guest_rate_limit('guest-checkout', repeat('a', 64), repeat('b', 64));
    raise exception 'Authenticated user executed the rate-limit consumer';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role service_role;
do $$
declare
  v_result record;
  v_attempt_key text := repeat('a', 64);
  v_ip_key text := repeat('b', 64);
  v_ip_threshold_key text := repeat('c', 64);
  v_independent_attempt_key text := repeat('d', 64);
  v_independent_ip_key text := repeat('e', 64);
  v_index integer;
begin
  -- The checkout attempt threshold is six requests per minute.
  for v_index in 1..6 loop
    select * into v_result from public.consume_guest_rate_limit('guest-checkout', v_ip_key, v_attempt_key);
    if not v_result.allowed or v_result.retry_after_seconds <> 0 then
      raise exception 'Below-limit checkout attempt was not allowed';
    end if;
  end loop;
  select * into v_result from public.consume_guest_rate_limit('guest-checkout', v_ip_key, v_attempt_key);
  if v_result.allowed or v_result.retry_after_seconds < 1 or v_result.retry_after_seconds > 60 then
    raise exception 'Checkout attempt threshold was not denied with a conservative retry delay';
  end if;

  -- The checkout IP threshold is ten requests per fifteen minutes. Distinct
  -- attempt keys isolate this check from the six-per-minute attempt threshold.
  for v_index in 1..10 loop
    select * into v_result
    from public.consume_guest_rate_limit('guest-checkout', v_ip_threshold_key, lpad(to_hex(v_index), 64, '0'));
    if not v_result.allowed then raise exception 'Below-limit checkout IP was not allowed'; end if;
  end loop;
  select * into v_result
  from public.consume_guest_rate_limit('guest-checkout', v_ip_threshold_key, lpad(to_hex(11), 64, '0'));
  if v_result.allowed or v_result.retry_after_seconds < 1 or v_result.retry_after_seconds > 900 then
    raise exception 'Checkout IP threshold was not denied with a conservative retry delay';
  end if;

  select * into v_result from public.consume_guest_rate_limit('guest-checkout', v_independent_ip_key, v_independent_attempt_key);
  if not v_result.allowed then raise exception 'Independent limiter subjects were not isolated'; end if;
  select * into v_result from public.consume_guest_rate_limit('create-stripe-payment-intent', v_ip_key, v_attempt_key);
  if not v_result.allowed then raise exception 'Endpoint scopes were not isolated'; end if;

  begin
    perform public.consume_guest_rate_limit('not-an-endpoint', v_ip_key, v_attempt_key);
    raise exception 'Invalid endpoint was accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.consume_guest_rate_limit('guest-checkout', '127.0.0.1', v_attempt_key);
    raise exception 'Raw IP identifier was accepted';
  exception when invalid_parameter_value then null;
  end;

end;
$$;

reset role;
insert into private.guest_rate_limit_windows(endpoint_scope, subject_kind, subject_hmac, window_started_at, request_count)
values
  ('guest-order-status', 'attempt', repeat('f', 64), date_trunc('minute', now()) - interval '2 hours', 60),
  ('guest-order-status', 'ip', repeat('1', 64), date_trunc('minute', now()) - interval '2 hours', 120);

set local role service_role;
do $$
declare
  v_result record;
begin
  -- A counter from an old window cannot affect the current fixed window.
  select * into v_result from public.consume_guest_rate_limit('guest-order-status', repeat('1', 64), repeat('f', 64));
  if not v_result.allowed then raise exception 'Fixed-window rollover was not isolated'; end if;
end;
$$;

reset role;
do $$
declare
  v_old_key text := repeat('2', 64);
  v_current_key text := repeat('3', 64);
  v_deleted integer;
begin
  -- Only HMAC-shaped identifiers are accepted by the table constraint; raw
  -- IPs, capabilities, and idempotency UUIDs have no storage column.
  if exists (
    select 1
    from private.guest_rate_limit_windows as rate_window
    where rate_window.subject_hmac !~ '^[0-9a-f]{64}$'
  ) then
    raise exception 'Rate-limit state contains a non-HMAC subject';
  end if;

  insert into private.guest_rate_limit_windows(endpoint_scope, subject_kind, subject_hmac, window_started_at, request_count)
  values
    ('guest-order-status', 'attempt', v_old_key, now() - interval '49 hours', 1),
    ('guest-order-status', 'attempt', v_current_key, now(), 1);
  v_deleted := public.purge_guest_rate_limit_windows();
  if v_deleted < 1
     or exists (select 1 from private.guest_rate_limit_windows as rate_window where rate_window.subject_hmac = v_old_key)
     or not exists (select 1 from private.guest_rate_limit_windows as rate_window where rate_window.subject_hmac = v_current_key) then
    raise exception 'Rate-limit retention purge was incorrect';
  end if;
end;
$$;

rollback;
