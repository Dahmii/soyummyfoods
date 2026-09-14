-- Phase 7F: durable, server-only fixed-window limiting for public guest flows.

create schema if not exists private;
revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

create table private.guest_rate_limit_windows (
  endpoint_scope text not null check (endpoint_scope in ('guest-checkout', 'create-stripe-payment-intent', 'guest-order-status')),
  subject_kind text not null check (subject_kind in ('attempt', 'ip')),
  subject_hmac text not null check (subject_hmac ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 0),
  primary key (endpoint_scope, subject_kind, subject_hmac, window_started_at)
);

create index guest_rate_limit_windows_purge_idx
  on private.guest_rate_limit_windows (window_started_at);

revoke all on table private.guest_rate_limit_windows from public;
revoke all on table private.guest_rate_limit_windows from anon;
revoke all on table private.guest_rate_limit_windows from authenticated;

create or replace function public.consume_guest_rate_limit(
  p_endpoint text,
  p_ip_key text,
  p_attempt_key text
)
returns table (
  allowed boolean,
  retry_after_seconds integer
)
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  v_now timestamptz := now();
  v_ip_limit integer;
  v_ip_window_seconds integer;
  v_attempt_limit integer;
  v_attempt_window_seconds integer;
  v_subject record;
  v_count integer;
  v_allowed boolean := true;
  v_retry_after_seconds integer := 0;
begin
  if p_endpoint is null or p_endpoint not in ('guest-checkout', 'create-stripe-payment-intent', 'guest-order-status') then
    raise exception 'Invalid guest rate-limit endpoint' using errcode = '22023';
  end if;

  if p_attempt_key is null or p_attempt_key !~ '^[0-9a-f]{64}$'
     or (p_ip_key is not null and p_ip_key !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid guest rate-limit subject' using errcode = '22023';
  end if;

  case p_endpoint
    when 'guest-checkout' then
      v_ip_limit := 10;
      v_ip_window_seconds := 900;
      v_attempt_limit := 6;
      v_attempt_window_seconds := 60;
    when 'create-stripe-payment-intent' then
      v_ip_limit := 30;
      v_ip_window_seconds := 900;
      v_attempt_limit := 10;
      v_attempt_window_seconds := 900;
    when 'guest-order-status' then
      v_ip_limit := 120;
      v_ip_window_seconds := 60;
      v_attempt_limit := 60;
      v_attempt_window_seconds := 60;
  end case;

  -- Lock/update subjects in a stable order. Both counters are consumed even
  -- when one is already over limit, avoiding a subject-specific side channel.
  for v_subject in
    select subject_kind, subject_hmac, limit_count, window_seconds
    from (
      values
        ('attempt'::text, p_attempt_key, v_attempt_limit, v_attempt_window_seconds),
        ('ip'::text, p_ip_key, v_ip_limit, v_ip_window_seconds)
    ) as subjects(subject_kind, subject_hmac, limit_count, window_seconds)
    where subject_hmac is not null
    order by subject_kind, subject_hmac
  loop
    insert into private.guest_rate_limit_windows as rate_window (
      endpoint_scope,
      subject_kind,
      subject_hmac,
      window_started_at,
      request_count
    )
    values (
      p_endpoint,
      v_subject.subject_kind,
      v_subject.subject_hmac,
      to_timestamp(floor(extract(epoch from v_now) / v_subject.window_seconds) * v_subject.window_seconds),
      1
    )
    on conflict (endpoint_scope, subject_kind, subject_hmac, window_started_at)
    do update set request_count =
      least(rate_window.request_count::bigint + 1, 2147483647)::integer
    returning rate_window.request_count into v_count;

    if v_count > v_subject.limit_count then
      v_allowed := false;
      v_retry_after_seconds := greatest(
        v_retry_after_seconds,
        greatest(
          1,
          ceil(extract(epoch from (
            to_timestamp(floor(extract(epoch from v_now) / v_subject.window_seconds) * v_subject.window_seconds)
            + make_interval(secs => v_subject.window_seconds)
            - v_now
          )))::integer
        )
      );
    end if;
  end loop;

  return query select v_allowed, v_retry_after_seconds;
end;
$$;

create or replace function public.purge_guest_rate_limit_windows()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  v_deleted integer;
begin
  delete from private.guest_rate_limit_windows as rate_window
  where rate_window.window_started_at < now() - interval '48 hours';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.consume_guest_rate_limit(text, text, text) from public;
revoke all on function public.consume_guest_rate_limit(text, text, text) from anon;
revoke all on function public.consume_guest_rate_limit(text, text, text) from authenticated;
grant execute on function public.consume_guest_rate_limit(text, text, text) to service_role;

revoke all on function public.purge_guest_rate_limit_windows() from public;
revoke all on function public.purge_guest_rate_limit_windows() from anon;
revoke all on function public.purge_guest_rate_limit_windows() from authenticated;
grant execute on function public.purge_guest_rate_limit_windows() to service_role;
