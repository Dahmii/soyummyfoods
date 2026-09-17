-- Phase 8E: safe post-payment receipt-issuance failure observability.
create or replace function public.record_receipt_issuance_failure(
  p_order_id uuid,
  p_error_code text
) returns void language plpgsql security definer set search_path = pg_catalog as $$
begin
  if p_order_id is null or nullif(btrim(p_error_code), '') is null
     or btrim(p_error_code) !~ '^[a-z0-9_]{1,100}$' then
    raise exception 'Invalid receipt issuance failure evidence' using errcode = '22023';
  end if;
  insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, old_values, new_values)
  values (null, 'receipt_issuance_failed', 'order', p_order_id, null,
    jsonb_build_object('operation','receipt_issuance_failed','error_code',btrim(p_error_code),'origin','stripe_webhook'));
end;
$$;
revoke all on function public.record_receipt_issuance_failure(uuid,text) from public, anon, authenticated;
grant execute on function public.record_receipt_issuance_failure(uuid,text) to service_role;
