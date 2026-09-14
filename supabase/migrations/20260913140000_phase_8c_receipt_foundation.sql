-- Phase 8C: immutable receipt records for normal verified Stripe successes.
-- Rendering, private storage, guest access, email, and invoices are deferred.

create sequence public.financial_document_receipt_number_seq
  as bigint
  start with 1
  increment by 1
  minvalue 1
  no cycle;

revoke all on sequence public.financial_document_receipt_number_seq from public;
revoke all on sequence public.financial_document_receipt_number_seq from anon;
revoke all on sequence public.financial_document_receipt_number_seq from authenticated;

create table public.financial_documents (
  id uuid primary key default gen_random_uuid(),
  document_type text not null check (document_type in ('receipt')),
  document_number text not null unique check (document_number ~ '^RCPT-[0-9]{10}$'),
  order_id uuid not null references public.orders(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  issued_at timestamptz not null default now(),
  issuer_snapshot jsonb not null,
  customer_snapshot jsonb not null,
  financial_snapshot jsonb not null,
  issued_by uuid references public.profiles(id) on delete restrict,
  issuance_origin text not null check (issuance_origin in ('system', 'authenticated_admin')),
  created_at timestamptz not null default now(),
  unique (order_id),
  unique (payment_id),
  constraint financial_documents_receipt_snapshot_shape_check check (
    jsonb_typeof(issuer_snapshot) = 'object'
    and jsonb_typeof(customer_snapshot) = 'object'
    and jsonb_typeof(financial_snapshot) = 'object'
    and financial_snapshot ? 'order_number'
    and financial_snapshot ? 'items'
    and jsonb_typeof(financial_snapshot->'items') = 'array'
  )
);

create index financial_documents_issued_at_idx
  on public.financial_documents (issued_at desc, id desc);

create or replace function public.prevent_financial_document_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Issued financial documents are immutable' using errcode = '42501';
end;
$$;

create trigger financial_documents_immutable_before_mutation
before update or delete on public.financial_documents
for each row execute function public.prevent_financial_document_mutation();

alter table public.audit_logs drop constraint audit_logs_entity_type_check;
alter table public.audit_logs add constraint audit_logs_entity_type_check
  check (entity_type in (
    'category',
    'product',
    'product_image',
    'business_settings',
    'delivery_zone',
    'inventory',
    'order',
    'payment',
    'user_role',
    'financial_document'
  ));

create or replace function public.issue_paid_order_receipt(
  p_order_id uuid
)
returns public.financial_documents
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_actor_id uuid := auth.uid();
  v_origin text := case when v_actor_id is null then 'system' else 'authenticated_admin' end;
  v_order public.orders;
  v_payment public.payments;
  v_settings public.business_settings;
  v_document public.financial_documents;
  v_items jsonb;
  v_receipt_number text;
  v_success_count integer := 0;
begin
  if p_order_id is null then
    raise exception 'Receipt order is required' using errcode = '22023';
  end if;

  select order_row.* into v_order
  from public.orders as order_row
  where order_row.id = p_order_id
  for update;
  if not found then
    raise exception 'Order not found' using errcode = '23503';
  end if;

  select document_row.* into v_document
  from public.financial_documents as document_row
  where document_row.order_id = v_order.id
  for update;
  if found then
    return v_document;
  end if;

  if v_order.status not in (
    'confirmed'::public.order_status,
    'preparing'::public.order_status,
    'ready'::public.order_status,
    'completed'::public.order_status
  ) then
    raise exception 'Order is not eligible for a receipt' using errcode = '23514';
  end if;

  for v_payment in
    select payment_row.*
    from public.payments as payment_row
    where payment_row.order_id = v_order.id
      and payment_row.status = 'succeeded'::public.payment_status
      and payment_row.provider_succeeded_at is not null
    order by payment_row.provider_succeeded_at, payment_row.id
    for update
  loop
    v_success_count := v_success_count + 1;
    if v_success_count > 1 then
      raise exception 'Receipt issuance is ambiguous: multiple verified successful payments exist for this order'
        using errcode = '23514';
    end if;
  end loop;
  if v_success_count = 0 then
    raise exception 'Verified successful payment is required for a receipt' using errcode = '23514';
  end if;

  if v_payment.amount_minor <> (v_order.total * 100)::bigint
     or v_payment.currency_code <> v_order.currency_code then
    raise exception 'Verified payment does not match the order total' using errcode = '23514';
  end if;

  select settings_row.* into v_settings
  from public.business_settings as settings_row
  where settings_row.id = 1
  for share;
  if not found then
    raise exception 'Business receipt identity is not configured' using errcode = '23503';
  end if;

  select jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'product_slug', item_row.product_slug_snapshot,
      'product_name', item_row.product_name_snapshot,
      'portion_note', item_row.portion_note_snapshot,
      'quantity', item_row.quantity,
      'unit_price', item_row.unit_price,
      'line_subtotal', item_row.line_subtotal
    ))
    order by item_row.created_at, item_row.id
  ) into v_items
  from public.order_items as item_row
  where item_row.order_id = v_order.id;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise exception 'Order has no immutable item snapshots' using errcode = '23514';
  end if;

  v_receipt_number := 'RCPT-' || lpad(nextval('public.financial_document_receipt_number_seq')::text, 10, '0');

  insert into public.financial_documents (
    document_type,
    document_number,
    order_id,
    payment_id,
    issued_at,
    issuer_snapshot,
    customer_snapshot,
    financial_snapshot,
    issued_by,
    issuance_origin
  ) values (
    'receipt',
    v_receipt_number,
    v_order.id,
    v_payment.id,
    now(),
    jsonb_strip_nulls(jsonb_build_object(
      'business_name', v_settings.business_name,
      'legal_name', v_settings.legal_name,
      'email', v_settings.email,
      'phone', v_settings.phone,
      'whatsapp_number', v_settings.whatsapp_number,
      'address_line_1', v_settings.address_line_1,
      'address_line_2', v_settings.address_line_2,
      'city', v_settings.city,
      'postcode', v_settings.postcode,
      'country', v_settings.country,
      'currency_code', v_settings.currency_code
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'name', v_order.customer_name,
      'email', v_order.customer_email,
      'phone', v_order.customer_phone,
      'delivery_address', v_order.delivery_address,
      'postcode', v_order.postcode_snapshot,
      'delivery_zone_name', v_order.delivery_zone_name_snapshot
    )),
    jsonb_strip_nulls(jsonb_build_object(
      'order_number', v_order.order_number,
      'order_created_at', v_order.created_at,
      'currency_code', v_order.currency_code,
      'subtotal', v_order.subtotal,
      'delivery_fee', v_order.delivery_fee,
      'discount_amount', v_order.discount_amount,
      'tax_amount', v_order.tax_amount,
      'tax_label', v_order.tax_label_snapshot,
      'tax_rate_percent', v_order.tax_rate_percent_snapshot,
      'total', v_order.total,
      'items', v_items,
      'payment', jsonb_strip_nulls(jsonb_build_object(
        'provider', v_payment.provider,
        'amount_minor', v_payment.amount_minor,
        'provider_payment_intent_id', v_payment.provider_payment_intent_id,
        'provider_charge_id', v_payment.provider_charge_id,
        'provider_succeeded_at', v_payment.provider_succeeded_at
      ))
    )),
    v_actor_id,
    v_origin
  ) returning * into v_document;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    old_values,
    new_values
  ) values (
    v_actor_id,
    'insert',
    'financial_document',
    v_document.id,
    null,
    jsonb_build_object(
      'document_type', v_document.document_type,
      'document_number', v_document.document_number,
      'order_id', v_document.order_id,
      'payment_id', v_document.payment_id,
      'origin', v_document.issuance_origin
    )
  );

  return v_document;
end;
$$;

alter table public.financial_documents enable row level security;

revoke all on table public.financial_documents from public;
revoke all on table public.financial_documents from anon;
revoke all on table public.financial_documents from authenticated;

revoke all on function public.prevent_financial_document_mutation() from public;
revoke all on function public.issue_paid_order_receipt(uuid) from public;
revoke all on function public.issue_paid_order_receipt(uuid) from anon;
revoke all on function public.issue_paid_order_receipt(uuid) from authenticated;
grant execute on function public.issue_paid_order_receipt(uuid) to service_role;

comment on table public.financial_documents is
  'Immutable issued financial documents. Phase 8C supports receipts only; rendering and storage are deferred.';
comment on function public.issue_paid_order_receipt(uuid) is
  'Service-role receipt issuance for normal verified successful payments. Idempotent per order and payment.';
