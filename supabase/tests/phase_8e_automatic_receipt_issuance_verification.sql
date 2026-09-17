-- Phase 8E disposable verification. Run after Phases 1-8E; rolled back.
begin;
do $$
declare v_definition text;
begin
  if has_function_privilege('anon','public.record_receipt_issuance_failure(uuid,text)','EXECUTE') or has_function_privilege('authenticated','public.record_receipt_issuance_failure(uuid,text)','EXECUTE') or not has_function_privilege('service_role','public.record_receipt_issuance_failure(uuid,text)','EXECUTE') then raise exception 'Failure-audit helper grants are wrong'; end if;
  select pg_get_functiondef('public.process_verified_stripe_payment_success(text,text,text,uuid,uuid,bigint,text,timestamptz,text)'::regprocedure) into v_definition;
  if position('issue_paid_order_receipt' in lower(v_definition)) <> 0 then raise exception 'Receipt issuance is inside payment transaction'; end if;
  if exists(select 1 from pg_attribute where attrelid='public.orders'::regclass and attname in ('receipt_access_capability_hash','receipt_access_expires_at')) then raise exception 'Guest receipt schema remains'; end if;
  if to_regprocedure('public.validate_guest_receipt_access(uuid,text)') is not null
     or exists (select 1 from pg_proc where prosrc ilike '%guest-receipt-access%') then
    raise exception 'Guest receipt access infrastructure remains';
  end if;
end $$;

set local role service_role;
do $$
declare
  c uuid; p uuid; i uuid; o uuid; pay uuid; r public.financial_documents;
  repeat_r public.financial_documents; moves integer; seq bigint; outcome text;
  failed uuid; failed_pay uuid;
  v_token text := lower(replace(gen_random_uuid()::text, '-', ''));
  v_normal_order_number text;
  v_failure_order_number text;
  v_normal_intent_id text;
  v_failure_intent_id text;
  v_normal_event_id text;
  v_failure_event_id text;
begin
  v_normal_order_number := 'SYF-8E-' || upper(substr(v_token, 1, 12));
  v_failure_order_number := 'SYF-8E-' || upper(substr(v_token, 13, 12));
  v_normal_intent_id := 'pi_phase8e_' || substr(v_token, 1, 18);
  v_failure_intent_id := 'pi_phase8e_' || substr(v_token, 19, 18);
  v_normal_event_id := 'evt_phase8e_' || substr(v_token, 1, 18);
  v_failure_event_id := 'evt_phase8e_' || substr(v_token, 19, 18);
  select id into c from public.categories order by display_order limit 1;
  if c is null or not exists(select 1 from public.business_settings where id=1) then raise exception 'Seeded category/settings required'; end if;
  insert into public.products(category_id,slug,name,description,base_price,prep_time_minutes,status,is_available,display_order) values(c,'phase-8e-verify','Phase 8E item','Disposable fixture',10,1,'active',true,99980) returning id into p;
  select id into i from public.configure_product_inventory(p,true,null); perform public.adjust_inventory(i,'stock_added',4,null);
  insert into public.orders(order_number,idempotency_key,request_fingerprint,status,customer_name,customer_email,customer_phone,delivery_address,postcode_snapshot,delivery_zone_name_snapshot,subtotal,delivery_fee,tax_amount,total,currency_code,reservation_expires_at) values(v_normal_order_number,gen_random_uuid(),'phase-8e-normal-' || v_token,'pending_payment','Phase 8E','p8e@example.test','1234567','10 Test Street','P8E','Phase 8E',10,0,0,10,'GBP',now()+interval '10 minutes') returning id into o;
  insert into public.order_items(order_id,product_id,product_slug_snapshot,product_name_snapshot,quantity,unit_price,line_subtotal) values(o,p,'phase-8e-verify','Phase 8E item',1,10,10);
  update public.inventory set quantity_reserved=1 where id=i; insert into public.inventory_movements(inventory_id,product_id,movement_type,quantity_delta,quantity_before,quantity_after,reserved_delta,reserved_before,reserved_after,order_id,reference_type,reference_id) values(i,p,'order_reservation',0,4,4,1,0,1,o,'order',o);
  insert into public.payments(order_id,provider,status,amount_minor,currency_code,attempt_sequence,payment_capability_hash,provider_payment_intent_id) values(o,'stripe','payment_intent_attached',1000,'GBP',1,repeat('a',64),v_normal_intent_id) returning id into pay;
  select success.outcome into outcome from public.process_verified_stripe_payment_success(v_normal_event_id,v_normal_intent_id,'ch_phase8e_' || substr(v_token, 1, 18),pay,o,1000,'GBP',now(),repeat('1',64)) as success;
  if outcome<>'processed' or (select status from public.orders where id=o)<>'confirmed' or (select status from public.payments where id=pay)<>'succeeded' or (select quantity_on_hand from public.inventory where id=i)<>3 or (select quantity_reserved from public.inventory where id=i)<>0 then raise exception 'Financial success state incorrect'; end if;
  select count(*) into moves from public.inventory_movements where order_id=o; select * into r from public.issue_paid_order_receipt(o); if r.order_id<>o or r.payment_id<>pay or r.document_number is null or r.financial_snapshot->'items' is null or r.issuer_snapshot='{}'::jsonb then raise exception 'Receipt snapshot incorrect'; end if;
  select last_value into seq from public.financial_document_receipt_number_seq; select * into repeat_r from public.issue_paid_order_receipt(o);
  if repeat_r.id<>r.id or repeat_r.document_number<>r.document_number or (select count(*) from public.financial_documents where order_id=o)<>1 or (select count(*) from public.inventory_movements where order_id=o)<>moves or (select last_value from public.financial_document_receipt_number_seq)<>seq then raise exception 'Duplicate recovery was not idempotent'; end if;
  insert into public.orders(order_number,idempotency_key,request_fingerprint,status,customer_name,customer_email,customer_phone,delivery_address,postcode_snapshot,delivery_zone_name_snapshot,subtotal,delivery_fee,tax_amount,total,currency_code,reservation_expires_at) values(v_failure_order_number,gen_random_uuid(),'phase-8e-failure-' || v_token,'pending_payment','Failure','failure@example.test','1234567','10 Test Street','P8E','Phase 8E',10,0,0,10,'GBP',now()+interval '10 minutes') returning id into failed;
  insert into public.payments(order_id,provider,status,amount_minor,currency_code,attempt_sequence,payment_capability_hash,provider_payment_intent_id) values(failed,'stripe','payment_intent_attached',1000,'GBP',1,repeat('b',64),v_failure_intent_id) returning id into failed_pay;
  select success.outcome into outcome from public.process_verified_stripe_payment_success(v_failure_event_id,v_failure_intent_id,'ch_phase8e_' || substr(v_token, 19, 18),failed_pay,failed,1000,'GBP',now(),repeat('2',64)) as success;
  if outcome <> 'processed' then raise exception 'Failure-fixture financial success did not process'; end if;
  begin perform public.issue_paid_order_receipt(failed); raise exception 'Receipt issued without items'; exception when check_violation then null; end;
  perform public.record_receipt_issuance_failure(failed,'receipt_snapshot_missing');
  if (select status from public.orders where id=failed)<>'confirmed' or (select status from public.payments where id=failed_pay)<>'succeeded' or not exists(select 1 from public.audit_logs where entity_type='order' and entity_id=failed and action='receipt_issuance_failed' and new_values=jsonb_build_object('operation','receipt_issuance_failed','error_code','receipt_snapshot_missing','origin','stripe_webhook')) then raise exception 'Failure isolation/audit incorrect'; end if;
  if exists(select 1 from public.audit_logs where entity_id=failed and new_values::text ~ '(capability|customer|payload|secret)') then raise exception 'Failure audit leaked data'; end if;
end $$;
reset role; set local role anon;
do $$ begin begin perform public.record_receipt_issuance_failure('00000000-0000-4000-8000-0000000008e1','receipt_failure'); raise exception 'Anon wrote audit'; exception when insufficient_privilege then null; end; end $$;
reset role; rollback;
