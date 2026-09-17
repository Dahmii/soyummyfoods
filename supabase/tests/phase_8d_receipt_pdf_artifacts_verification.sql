-- Phase 8D artifact-schema verification. Run after Phases 1-8D in a
-- disposable database. Storage/PDF runtime behavior is covered by the paired
-- runtime smoke procedure because it requires a deployed Edge Function.

begin;

do $$
declare
  v_document_attnum smallint;
  v_register_definition text;
begin
  select attnum into v_document_attnum
  from pg_attribute
  where attrelid = 'public.financial_document_artifacts'::regclass
    and attname = 'financial_document_id'
    and not attisdropped;
  if not exists (
    select 1 from storage.buckets
    where id = 'financial-documents'
      and public = false
      and allowed_mime_types = array['application/pdf']::text[]
  ) then raise exception 'The private financial-documents PDF bucket is incorrect'; end if;
  if not exists (
    select 1 from pg_class
    where oid = 'public.financial_document_artifacts'::regclass
      and relrowsecurity
  ) then raise exception 'Artifact RLS is not enabled'; end if;
  if not exists (
    select 1 from pg_constraint as constraint_row
    where constraint_row.conrelid = 'public.financial_document_artifacts'::regclass
      and constraint_row.contype = 'u'
      and array_length(constraint_row.conkey, 1) = 2
      and v_document_attnum = any (constraint_row.conkey)
  ) then raise exception 'Canonical per-receipt artifact uniqueness is missing'; end if;
  if not exists (
    select 1
    from pg_constraint as constraint_row
    join pg_attribute as source_column
      on source_column.attrelid = constraint_row.conrelid
     and source_column.attnum = any (constraint_row.conkey)
    join pg_attribute as target_column
      on target_column.attrelid = constraint_row.confrelid
     and target_column.attnum = any (constraint_row.confkey)
    where constraint_row.conrelid = 'public.financial_document_artifacts'::regclass
      and constraint_row.confrelid = 'public.financial_documents'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.confdeltype = 'r'
      and source_column.attname = 'financial_document_id'
      and target_column.attname = 'id'
  ) then raise exception 'Artifact financial-history FK must restrict deletion'; end if;
  if has_table_privilege('anon', 'public.financial_document_artifacts', 'INSERT')
     or has_table_privilege('authenticated', 'public.financial_document_artifacts', 'INSERT')
     or has_table_privilege('anon', 'public.financial_document_artifacts', 'UPDATE')
     or has_table_privilege('authenticated', 'public.financial_document_artifacts', 'UPDATE')
     or has_table_privilege('anon', 'public.financial_document_artifacts', 'DELETE')
     or has_table_privilege('authenticated', 'public.financial_document_artifacts', 'DELETE')
     or has_function_privilege('anon', 'public.register_receipt_pdf_artifact(uuid,text,integer,text,text,uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.register_receipt_pdf_artifact(uuid,text,integer,text,text,uuid,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.register_receipt_pdf_artifact(uuid,text,integer,text,text,uuid,text)', 'EXECUTE') then
    raise exception 'Artifact browser/write permission boundary is incorrect';
  end if;
  if not exists (
    select 1 from pg_trigger as trigger_row
    where trigger_row.tgrelid = 'public.financial_document_artifacts'::regclass
      and trigger_row.tgname = 'financial_document_artifacts_immutable_before_mutation'
      and trigger_row.tgfoid = 'public.prevent_financial_document_artifact_mutation()'::regprocedure
      and not trigger_row.tgisinternal
      and (trigger_row.tgtype::integer & 1) = 1
      and (trigger_row.tgtype::integer & 2) = 2
      and (trigger_row.tgtype::integer & 8) = 8
      and (trigger_row.tgtype::integer & 16) = 16
  ) then raise exception 'Artifact immutability trigger is incorrect'; end if;
  if (select count(*) from pg_policies
      where schemaname = 'storage' and tablename = 'objects'
        and policyname in (
          'financial_documents_no_anon_read',
          'financial_documents_no_authenticated_read',
          'financial_documents_no_anon_write',
          'financial_documents_no_authenticated_write'
        )
        and permissive = 'RESTRICTIVE') <> 4 then
    raise exception 'Private receipt Storage denial policies are missing';
  end if;
  select pg_get_functiondef('public.register_receipt_pdf_artifact(uuid,text,integer,text,text,uuid,text)'::regprocedure)
    into v_register_definition;
  if position('pg_advisory_xact_lock' in lower(v_register_definition)) = 0
     or position('canonical receipt artifact metadata conflicts' in lower(v_register_definition)) = 0
     or position('v_artifact.sha256_hex <> p_sha256_hex' in lower(v_register_definition)) = 0
     or position('v_artifact.byte_size <> p_byte_size' in lower(v_register_definition)) = 0
     or position('v_artifact.storage_object_path <> p_storage_object_path' in lower(v_register_definition)) = 0 then
    raise exception 'Artifact registration conflict detection is incorrect';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin perform public.register_receipt_pdf_artifact('00000000-0000-4000-8000-0000000008d1', 'receipts/00000000-0000-4000-8000-0000000008d1.pdf', 1, repeat('a', 64), 'test'); raise exception 'Anon registered an artifact'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
set local role authenticated;
do $$
begin
  begin perform public.register_receipt_pdf_artifact('00000000-0000-4000-8000-0000000008d1', 'receipts/00000000-0000-4000-8000-0000000008d1.pdf', 1, repeat('a', 64), 'test'); raise exception 'Authenticated user registered an artifact'; exception when insufficient_privilege then null; end;
end;
$$;

reset role;
rollback;
