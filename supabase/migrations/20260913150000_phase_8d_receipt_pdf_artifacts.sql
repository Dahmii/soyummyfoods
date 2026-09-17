-- Phase 8D: immutable receipt-PDF artifacts in private Storage.
-- Receipt issuance and financial snapshots remain owned by Phase 8C.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('financial-documents', 'financial-documents', false, 5242880, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "financial_documents_no_anon_read"
on storage.objects as restrictive for select to anon
using (bucket_id <> 'financial-documents');

create policy "financial_documents_no_authenticated_read"
on storage.objects as restrictive for select to authenticated
using (bucket_id <> 'financial-documents');

create policy "financial_documents_no_anon_write"
on storage.objects as restrictive for all to anon
using (bucket_id <> 'financial-documents')
with check (bucket_id <> 'financial-documents');

create policy "financial_documents_no_authenticated_write"
on storage.objects as restrictive for all to authenticated
using (bucket_id <> 'financial-documents')
with check (bucket_id <> 'financial-documents');

create table public.financial_document_artifacts (
  id uuid primary key default gen_random_uuid(),
  financial_document_id uuid not null references public.financial_documents(id) on delete restrict,
  artifact_type text not null check (artifact_type = 'receipt_pdf'),
  storage_bucket text not null check (storage_bucket = 'financial-documents'),
  storage_object_path text not null check (storage_object_path ~ '^receipts/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.]pdf$'),
  mime_type text not null check (mime_type = 'application/pdf'),
  byte_size integer not null check (byte_size > 0 and byte_size <= 5242880),
  sha256_hex text not null check (sha256_hex ~ '^[0-9a-f]{64}$'),
  generator_version text not null check (char_length(btrim(generator_version)) between 1 and 100),
  generated_at timestamptz not null default now(),
  generated_by uuid references public.profiles(id) on delete restrict,
  generation_origin text not null check (generation_origin in ('system', 'authenticated_admin')),
  created_at timestamptz not null default now(),
  unique (financial_document_id, artifact_type),
  unique (storage_bucket, storage_object_path)
);

create index financial_document_artifacts_document_idx
  on public.financial_document_artifacts (financial_document_id, generated_at desc, id desc);

create or replace function public.prevent_financial_document_artifact_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Financial document artifacts are immutable' using errcode = '42501';
end;
$$;

create trigger financial_document_artifacts_immutable_before_mutation
before update or delete on public.financial_document_artifacts
for each row execute function public.prevent_financial_document_artifact_mutation();

create or replace function public.register_receipt_pdf_artifact(
  p_financial_document_id uuid,
  p_storage_object_path text,
  p_byte_size integer,
  p_sha256_hex text,
  p_generator_version text,
  p_generated_by uuid default null,
  p_generation_origin text default 'system'
)
returns public.financial_document_artifacts
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_artifact public.financial_document_artifacts;
  v_document_id uuid;
  v_expected_path text;
begin
  if p_financial_document_id is null
     or p_storage_object_path is null
     or p_byte_size is null
     or p_sha256_hex is null
     or p_generator_version is null then
    raise exception 'Receipt artifact metadata is required' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('public.register_receipt_pdf_artifact:' || p_financial_document_id::text)::bigint
  );

  select artifact_row.* into v_artifact
  from public.financial_document_artifacts as artifact_row
  where artifact_row.financial_document_id = p_financial_document_id
    and artifact_row.artifact_type = 'receipt_pdf'
  for update;
  if found then
    if v_artifact.artifact_type <> 'receipt_pdf'
       or v_artifact.storage_bucket <> 'financial-documents'
       or v_artifact.storage_object_path <> p_storage_object_path
       or v_artifact.mime_type <> 'application/pdf'
       or v_artifact.byte_size <> p_byte_size
       or v_artifact.sha256_hex <> p_sha256_hex
       or v_artifact.generator_version <> btrim(p_generator_version) then
      raise exception 'Canonical receipt artifact metadata conflicts with the existing artifact' using errcode = '23514';
    end if;
    return v_artifact;
  end if;

  select document_row.id into v_document_id
  from public.financial_documents as document_row
  where document_row.id = p_financial_document_id
    and document_row.document_type = 'receipt'
  for key share;
  if not found then
    raise exception 'Receipt document was not found' using errcode = '23503';
  end if;

  v_expected_path := 'receipts/' || p_financial_document_id::text || '.pdf';
  if p_storage_object_path <> v_expected_path
     or p_byte_size <= 0
     or p_byte_size > 5242880
     or p_sha256_hex !~ '^[0-9a-f]{64}$'
     or char_length(btrim(p_generator_version)) not between 1 and 100
     or p_generation_origin not in ('system', 'authenticated_admin')
     or (p_generation_origin = 'authenticated_admin' and p_generated_by is null) then
    raise exception 'Receipt artifact metadata is invalid' using errcode = '22023';
  end if;

  insert into public.financial_document_artifacts (
    financial_document_id, artifact_type, storage_bucket, storage_object_path,
    mime_type, byte_size, sha256_hex, generator_version, generated_by, generation_origin
  ) values (
    p_financial_document_id, 'receipt_pdf', 'financial-documents', p_storage_object_path,
    'application/pdf', p_byte_size, p_sha256_hex, btrim(p_generator_version), p_generated_by, p_generation_origin
  ) returning * into v_artifact;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    p_generated_by, 'insert', 'financial_document', p_financial_document_id, null,
    jsonb_build_object(
      'artifact_id', v_artifact.id,
      'artifact_type', v_artifact.artifact_type,
      'storage_bucket', v_artifact.storage_bucket,
      'storage_object_path', v_artifact.storage_object_path,
      'sha256_hex', v_artifact.sha256_hex,
      'origin', v_artifact.generation_origin
    )
  );

  return v_artifact;
end;
$$;

create or replace function public.get_admin_order_receipt_artifact_status(
  p_order_id uuid
)
returns table (
  financial_document_id uuid,
  document_number text,
  artifact_id uuid,
  generated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_manager_or_owner() then
    raise exception 'Receipt access permission required' using errcode = '42501';
  end if;
  return query
  select
    document_row.id,
    document_row.document_number,
    artifact_row.id,
    artifact_row.generated_at
  from public.financial_documents as document_row
  left join public.financial_document_artifacts as artifact_row
    on artifact_row.financial_document_id = document_row.id
   and artifact_row.artifact_type = 'receipt_pdf'
  where document_row.order_id = p_order_id
    and document_row.document_type = 'receipt';
end;
$$;

alter table public.financial_document_artifacts enable row level security;

revoke all on table public.financial_document_artifacts from public;
revoke all on table public.financial_document_artifacts from anon;
revoke all on table public.financial_document_artifacts from authenticated;

revoke all on function public.prevent_financial_document_artifact_mutation() from public;
revoke all on function public.register_receipt_pdf_artifact(uuid, text, integer, text, text, uuid, text) from public;
revoke all on function public.register_receipt_pdf_artifact(uuid, text, integer, text, text, uuid, text) from anon;
revoke all on function public.register_receipt_pdf_artifact(uuid, text, integer, text, text, uuid, text) from authenticated;
grant execute on function public.register_receipt_pdf_artifact(uuid, text, integer, text, text, uuid, text) to service_role;

revoke all on function public.get_admin_order_receipt_artifact_status(uuid) from public;
revoke all on function public.get_admin_order_receipt_artifact_status(uuid) from anon;
revoke all on function public.get_admin_order_receipt_artifact_status(uuid) from service_role;
grant execute on function public.get_admin_order_receipt_artifact_status(uuid) to authenticated;

comment on table public.financial_document_artifacts is
  'Immutable metadata for canonical private receipt rendering artifacts. Phase 8D supports one PDF per receipt.';
comment on function public.register_receipt_pdf_artifact(uuid, text, integer, text, text, uuid, text) is
  'Service-role-only, idempotent registration of a canonical private receipt PDF artifact.';
