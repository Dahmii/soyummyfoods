-- Phase 8C receipt-foundation verification. Run after Phases 1-8C in a
-- disposable database only. Every fixture and mutation is rolled back.

begin;

do $$
declare
  v_order_id_attnum smallint;
  v_payment_id_attnum smallint;
  v_number_attnum smallint;
  v_issue_definition text;
begin
  select attnum into v_order_id_attnum from pg_attribute where attrelid = 'public.financial_documents'::regclass and attname = 'order_id' and not attisdropped;
  select attnum into v_payment_id_attnum from pg_attribute where attrelid = 'public.financial_documents'::regclass and attname = 'payment_id' and not attisdropped;
  select attnum into v_number_attnum from pg_attribute where attrelid = 'public.financial_documents'::regclass and attname = 'document_number' and not attisdropped;
  if not exists (select 1 from pg_class where oid = 'public.financial_documents'::regclass)
     or not exists (select 1 from pg_class where oid = 'public.financial_document_receipt_number_seq'::regclass and relkind = 'S') then
    raise exception 'Phase 8C financial-document foundation is missing';
  end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.financial_documents'::regclass
      and constraint_row.contype = 'u'
      and array_length(constraint_row.conkey, 1) = 1
      and constraint_row.conkey[1] = v_order_id_attnum
  ) or not exists (
    select 1 from pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.financial_documents'::regclass
      and constraint_row.contype = 'u'
      and array_length(constraint_row.conkey, 1) = 1
      and constraint_row.conkey[1] = v_payment_id_attnum
  ) or not exists (
    select 1 from pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.financial_documents'::regclass
      and constraint_row.contype = 'u'
      and array_length(constraint_row.conkey, 1) = 1
      and constraint_row.conkey[1] = v_number_attnum
  ) then
    raise exception 'Receipt idempotency or number uniqueness constraints are missing';
  end if;
  if not exists (
    select 1 from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'public.financial_documents'::regclass
      and trigger_row.tgname = 'financial_documents_immutable_before_mutation'
      and trigger_row.tgfoid = 'public.prevent_financial_document_mutation()'::regprocedure
      and not trigger_row.tgisinternal
      and (trigger_row.tgtype::integer & 1) = 1
      and (trigger_row.tgtype::integer & 2) = 2
      and (trigger_row.tgtype::integer & 8) = 8
      and (trigger_row.tgtype::integer & 16) = 16
  ) then raise exception 'Receipt immutability trigger is incorrect'; end if;
  if has_table_privilege('anon', 'public.financial_documents', 'SELECT')
     or has_table_privilege('authenticated', 'public.financial_documents', 'SELECT')
     or has_table_privilege('anon', 'public.financial_documents', 'INSERT')
     or has_table_privilege('authenticated', 'public.financial_documents', 'INSERT')
     or has_table_privilege('anon', 'public.financial_documents', 'UPDATE')
     or has_table_privilege('authenticated', 'public.financial_documents', 'UPDATE')
     or has_table_privilege('anon', 'public.financial_documents', 'DELETE')
     or has_table_privilege('authenticated', 'public.financial_documents', 'DELETE')
     or has_function_privilege('anon', 'public.issue_paid_order_receipt(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.issue_paid_order_receipt(uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.issue_paid_order_receipt(uuid)', 'EXECUTE') then
    raise exception 'Receipt browser permission boundary is incorrect';
  end if;
  if has_sequence_privilege('anon', 'public.financial_document_receipt_number_seq', 'USAGE')
     or has_sequence_privilege('anon', 'public.financial_document_receipt_number_seq', 'SELECT')
     or has_sequence_privilege('anon', 'public.financial_document_receipt_number_seq', 'UPDATE')
     or has_sequence_privilege('authenticated', 'public.financial_document_receipt_number_seq', 'USAGE')
     or has_sequence_privilege('authenticated', 'public.financial_document_receipt_number_seq', 'SELECT')
     or has_sequence_privilege('authenticated', 'public.financial_document_receipt_number_seq', 'UPDATE') then
    raise exception 'A browser role retains receipt-number sequence privileges';
  end if;
  if not exists (
    select 1
    from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.financial_documents'::regclass
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'r'
      and source_column.attname = 'issued_by' and target_column.attname = 'id'
  ) then raise exception 'Receipt issuer attribution must restrict profile deletion'; end if;
  select pg_get_functiondef('public.issue_paid_order_receipt(uuid)'::regprocedure) into v_issue_definition;
  if position('for update' in lower(v_issue_definition)) = 0
     or position('nextval(' in lower(v_issue_definition)) = 0
     or position('late_success_requires_reconciliation' in lower(v_issue_definition)) <> 0
     or position('status = ''succeeded''::public.payment_status' in lower(v_issue_definition)) = 0
     or position('v_success_count > 1' in lower(v_issue_definition)) = 0
     or position('v_success_count > 1' in lower(v_issue_definition)) > position('nextval(' in lower(v_issue_definition)) then
    raise exception 'Receipt eligibility or concurrency implementation is incorrect';
  end if;
  if not exists (
    select 1
    from pg_constraint as constraint_row
    join pg_attribute as source_column on source_column.attrelid = constraint_row.conrelid and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column on target_column.attrelid = constraint_row.confrelid and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.payments'::regclass
      and constraint_row.confrelid = 'public.profiles'::regclass
      and constraint_row.contype = 'f' and constraint_row.confdeltype = 'r'
      and source_column.attname = 'reconciliation_resolved_by' and target_column.attname = 'id'
  ) or not exists (
    select 1 from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'public.user_roles'::regclass
      and trigger_row.tgfoid = 'public.prevent_final_owner_removal()'::regprocedure
      and (trigger_row.tgtype::integer & 2) = 2
  ) then raise exception 'Phase 8A or Phase 8B invariant was weakened'; end if;
end;
$$;

set local role service_role;
do $$
declare
  v_category_id uuid;
  v_product_id uuid;
  v_paid_order_id uuid;
  v_unpaid_order_id uuid;
  v_failed_order_id uuid;
  v_late_order_id uuid;
  v_ambiguous_order_id uuid;
  v_paid_payment_id uuid;
  v_receipt public.financial_documents;
  v_repeat_receipt public.financial_documents;
  v_receipt_snapshot jsonb;
  v_issuer_snapshot jsonb;
  v_audit_count integer;
  v_sequence_last_value bigint;
begin
  select category_row.id into v_category_id from public.categories as category_row order by category_row.display_order limit 1;
  if v_category_id is null or not exists (select 1 from public.business_settings where id = 1) then
    raise exception 'Phase 8C verification requires seeded category and business settings';
  end if;

  insert into public.products(category_id, slug, name, description, base_price, prep_time_minutes, status, is_available, display_order)
  values (v_category_id, 'phase-8c-receipt-test', 'Phase 8C receipt item', 'Disposable receipt verification product.', 12.50, 1, 'draft', true, 99970)
  returning id into v_product_id;
  insert into public.product_images(product_id, storage_path, is_primary, display_order)
  values (v_product_id, '/phase-8c-test.jpg', true, 0);
  update public.products set status = 'active' where id = v_product_id;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values ('SYF-20260914-8C000001', gen_random_uuid(), 'phase-8c-paid', 'confirmed', 'Receipt Customer', 'receipt@example.test', '1234567', '10 Test Street', 'P8CTEST', 'Receipt test zone', 12.50, 2.50, 0, 0, 15.00, 'GBP', now() - interval '5 minutes')
  returning id into v_paid_order_id;
  insert into public.order_items(order_id, product_id, product_slug_snapshot, product_name_snapshot, portion_note_snapshot, quantity, unit_price, line_subtotal)
  values (v_paid_order_id, v_product_id, 'phase-8c-receipt-test', 'Phase 8C receipt item', 'Single portion', 1, 12.50, 12.50);
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values (v_paid_order_id, 'succeeded', 1500, 'GBP', repeat('a', 64), 'pi_phase8c_paid', 'ch_phase8c_paid', '2026-09-14 12:00:00+00')
  returning id into v_paid_payment_id;

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values ('SYF-20260914-8C000002', gen_random_uuid(), 'phase-8c-unpaid', 'pending_payment', 'Unpaid Customer', 'unpaid@example.test', '1234567', '10 Test Street', 'P8CTEST', 'Receipt test zone', 10, 0, 0, 0, 10, 'GBP', now() + interval '5 minutes')
  returning id into v_unpaid_order_id;
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash)
  values (v_unpaid_order_id, 'awaiting_payment_intent', 1000, 'GBP', repeat('b', 64));

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values ('SYF-20260914-8C000003', gen_random_uuid(), 'phase-8c-failed', 'pending_payment', 'Failed Customer', 'failed@example.test', '1234567', '10 Test Street', 'P8CTEST', 'Receipt test zone', 10, 0, 0, 0, 10, 'GBP', now() + interval '5 minutes')
  returning id into v_failed_order_id;
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_failure_code)
  values (v_failed_order_id, 'payment_failed', 1000, 'GBP', repeat('c', 64), 'card_declined');

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values ('SYF-20260914-8C000004', gen_random_uuid(), 'phase-8c-late', 'confirmed', 'Late Customer', 'late@example.test', '1234567', '10 Test Street', 'P8CTEST', 'Receipt test zone', 10, 0, 0, 0, 10, 'GBP', now() - interval '5 minutes')
  returning id into v_late_order_id;
  insert into public.payments(order_id, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values (v_late_order_id, 'late_success_requires_reconciliation', 1000, 'GBP', repeat('d', 64), 'pi_phase8c_late', 'ch_phase8c_late', '2026-09-14 12:00:00+00');

  insert into public.orders(order_number, idempotency_key, request_fingerprint, status, customer_name, customer_email, customer_phone, delivery_address, postcode_snapshot, delivery_zone_name_snapshot, subtotal, delivery_fee, discount_amount, tax_amount, total, currency_code, reservation_expires_at)
  values ('SYF-20260914-8C000005', gen_random_uuid(), 'phase-8c-ambiguous', 'confirmed', 'Ambiguous Customer', 'ambiguous@example.test', '1234567', '10 Test Street', 'P8CTEST', 'Receipt test zone', 10, 0, 0, 0, 10, 'GBP', now() - interval '5 minutes')
  returning id into v_ambiguous_order_id;
  insert into public.payments(order_id, attempt_sequence, status, amount_minor, currency_code, payment_capability_hash, provider_payment_intent_id, provider_charge_id, provider_succeeded_at)
  values
    (v_ambiguous_order_id, 1, 'succeeded', 1000, 'GBP', repeat('e', 64), 'pi_phase8c_ambiguous_1', 'ch_phase8c_ambiguous_1', '2026-09-14 12:00:00+00'),
    (v_ambiguous_order_id, 2, 'succeeded', 1000, 'GBP', repeat('f', 64), 'pi_phase8c_ambiguous_2', 'ch_phase8c_ambiguous_2', '2026-09-14 12:00:01+00');

  select * into v_receipt from public.issue_paid_order_receipt(v_paid_order_id);
  if v_receipt.document_type <> 'receipt'
     or v_receipt.order_id <> v_paid_order_id
     or v_receipt.payment_id <> v_paid_payment_id
     or v_receipt.document_number !~ '^RCPT-[0-9]{10}$'
     or v_receipt.financial_snapshot->>'order_number' <> 'SYF-20260914-8C000001'
     or v_receipt.financial_snapshot->'items'->0->>'product_name' <> 'Phase 8C receipt item'
     or v_receipt.financial_snapshot->'payment'->>'provider_payment_intent_id' <> 'pi_phase8c_paid'
     or v_receipt.financial_snapshot::text like '%payment_capability_hash%' then
    raise exception 'Eligible paid order receipt snapshot is incorrect';
  end if;
  v_receipt_snapshot := v_receipt.financial_snapshot;
  v_issuer_snapshot := v_receipt.issuer_snapshot;
  select count(*) into v_audit_count from public.audit_logs where entity_type = 'financial_document' and entity_id = v_receipt.id and action = 'insert';
  if v_audit_count <> 1 then raise exception 'Receipt issuance audit is missing'; end if;

  select * into v_repeat_receipt from public.issue_paid_order_receipt(v_paid_order_id);
  if v_repeat_receipt.id <> v_receipt.id
     or v_repeat_receipt.document_number <> v_receipt.document_number
     or (select count(*) from public.financial_documents where order_id = v_paid_order_id) <> 1
     or (select count(*) from public.audit_logs where entity_type = 'financial_document' and entity_id = v_receipt.id and action = 'insert') <> 1 then
    raise exception 'Receipt issuance was not idempotent';
  end if;

  begin perform public.issue_paid_order_receipt(v_unpaid_order_id); raise exception 'Unpaid order qualified for receipt'; exception when check_violation then null; end;
  begin perform public.issue_paid_order_receipt(v_failed_order_id); raise exception 'Failed payment qualified for receipt'; exception when check_violation then null; end;
  begin perform public.issue_paid_order_receipt(v_late_order_id); raise exception 'Late success qualified for receipt'; exception when check_violation then null; end;
  select last_value into v_sequence_last_value from public.financial_document_receipt_number_seq;
  begin perform public.issue_paid_order_receipt(v_ambiguous_order_id); raise exception 'Ambiguous successful payments qualified for receipt'; exception when check_violation then null; end;
  if exists (select 1 from public.financial_documents where order_id = v_ambiguous_order_id)
     or exists (
       select 1
       from public.audit_logs as audit_row
       where audit_row.entity_type = 'financial_document'
         and audit_row.new_values->>'order_id' = v_ambiguous_order_id::text
     )
     or (select last_value from public.financial_document_receipt_number_seq) <> v_sequence_last_value then
    raise exception 'Ambiguous receipt issuance created state or consumed a receipt number';
  end if;

  update public.products set name = 'Changed product name', base_price = 99.99 where id = v_product_id;
  update public.business_settings set business_name = 'Changed business name', address_line_1 = 'Changed issuer address' where id = 1;
  if (select financial_snapshot from public.financial_documents where id = v_receipt.id) is distinct from v_receipt_snapshot
     or (select issuer_snapshot from public.financial_documents where id = v_receipt.id) is distinct from v_issuer_snapshot
     or (select financial_snapshot->'items'->0->>'product_name' from public.financial_documents where id = v_receipt.id) <> 'Phase 8C receipt item' then
    raise exception 'Receipt relied on mutable product or business settings data';
  end if;

  begin update public.financial_documents set document_number = 'RCPT-9999999999' where id = v_receipt.id; raise exception 'Issued receipt was mutable'; exception when insufficient_privilege then null; end;
  begin delete from public.financial_documents where id = v_receipt.id; raise exception 'Issued receipt was deletable'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role anon;
do $$
begin
  begin perform nextval('public.financial_document_receipt_number_seq'); raise exception 'Anon allocated a receipt number'; exception when insufficient_privilege then null; end;
  begin insert into public.financial_documents(document_type, document_number, order_id, payment_id, issuer_snapshot, customer_snapshot, financial_snapshot, issuance_origin)
    values ('receipt', 'RCPT-9999999999', '00000000-0000-4000-8000-0000000008c1', '00000000-0000-4000-8000-0000000008c2', '{}'::jsonb, '{}'::jsonb, '{"order_number":"x","items":[]}'::jsonb, 'system');
    raise exception 'Anon inserted a financial document'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
do $$
begin
  begin perform nextval('public.financial_document_receipt_number_seq'); raise exception 'Authenticated user allocated a receipt number'; exception when insufficient_privilege then null; end;
  begin insert into public.financial_documents(document_type, document_number, order_id, payment_id, issuer_snapshot, customer_snapshot, financial_snapshot, issuance_origin)
    values ('receipt', 'RCPT-9999999998', '00000000-0000-4000-8000-0000000008c3', '00000000-0000-4000-8000-0000000008c4', '{}'::jsonb, '{}'::jsonb, '{"order_number":"x","items":[]}'::jsonb, 'system');
    raise exception 'Authenticated user inserted a financial document'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
rollback;
