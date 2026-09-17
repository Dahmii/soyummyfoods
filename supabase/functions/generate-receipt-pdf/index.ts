import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const BUCKET = 'financial-documents';
const GENERATOR_VERSION = 'receipt-pdf-v1';
const SIGNED_URL_TTL_SECONDS = 300;
const MAX_REQUEST_BYTES = 2048;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

type Json = Record<string, unknown>;
type ReceiptDocument = {
  id: string;
  document_type: string;
  document_number: string;
  issued_at: string;
  issuer_snapshot: Json;
  customer_snapshot: Json;
  financial_snapshot: Json;
};
type Artifact = {
  id: string;
  financial_document_id: string;
  storage_bucket: string;
  storage_object_path: string;
  mime_type: string;
  byte_size: number;
  sha256_hex: string;
  generator_version: string;
  generated_at: string;
};

const fail = (code: string, message: string, status: number) => new Response(
  JSON.stringify({ ok: false, code, message }),
  { status, headers: { ...headers, 'Content-Type': 'application/json' } }
);
const isRecord = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value);
const valueString = (record: Json, key: string): string | null => typeof record[key] === 'string' && record[key].trim() ? record[key].trim() : null;
const valueNumber = (record: Json, key: string): number => {
  const value = Number(record[key]);
  return Number.isFinite(value) ? value : 0;
};
const sha256Hex = async (bytes: Uint8Array): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
};
const secretKey = (): string | null => {
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (!raw) return null;
  try {
    const parsed: unknown = JSON.parse(raw);
    return isRecord(parsed) && typeof parsed.default === 'string' && parsed.default.trim() ? parsed.default.trim() : null;
  } catch { return null; }
};
const sanitizePdfText = (value: string): string => value
  .replace(/[\r\n\t]+/g, ' ')
  .replace(/[^\x20-\x7e]/g, '?');
const pdfText = (value: string): string => value.replace(/[\\()]/g, '\\$&');
const wrap = (value: string, max = 82): string[] => {
  const words = sanitizePdfText(value).trim().split(/\s+/).filter(Boolean);
  if (!words.length) return [];
  const lines: string[] = [];
  let line = '';
  const appendToken = (token: string) => {
    if (!line) line = token;
    else if (`${line} ${token}`.length <= max) line += ` ${token}`;
    else { lines.push(line); line = token; }
  };
  for (const word of words) {
    let remaining = word;
    while (remaining.length > max) {
      if (line) { lines.push(line); line = ''; }
      lines.push(remaining.slice(0, max));
      remaining = remaining.slice(max);
    }
    if (remaining) appendToken(remaining);
  }
  if (line) lines.push(line);
  return lines;
};
const amount = (value: number, currency: string): string => `${currency} ${value.toFixed(2)}`;
const hasPrefix = (bytes: Uint8Array, value: string): boolean => {
  const expected = new TextEncoder().encode(value);
  return expected.every((byte, index) => bytes[index] === byte);
};
const receiptPdfText = (bytes: Uint8Array): string => new TextDecoder().decode(bytes);
const isValidReceiptPdf = (bytes: Uint8Array, document: ReceiptDocument): boolean => {
  const orderNumber = valueString(document.financial_snapshot, 'order_number');
  const text = receiptPdfText(bytes);
  const eofPosition = text.lastIndexOf('%%EOF');
  if (bytes.length === 0 || !hasPrefix(bytes, '%PDF-') || eofPosition < 0 || text.slice(eofPosition + 5).trim() !== '') return false;
  return text.includes(`Receipt number: ${document.document_number}`)
    && orderNumber !== null
    && text.includes(`Order number: ${orderNumber}`);
};

function renderReceiptPdf(document: ReceiptDocument): Uint8Array {
  const issuer = document.issuer_snapshot;
  const customer = document.customer_snapshot;
  const financial = document.financial_snapshot;
  const currency = valueString(financial, 'currency_code') ?? 'GBP';
  const issuedDate = new Date(document.issued_at).toISOString().slice(0, 10);
  const lines: string[] = [
    'RECEIPT',
    ...wrap(valueString(issuer, 'business_name') ?? 'Business'),
    ...[valueString(issuer, 'legal_name'), valueString(issuer, 'address_line_1'), valueString(issuer, 'address_line_2'), valueString(issuer, 'city'), valueString(issuer, 'postcode'), valueString(issuer, 'country'), valueString(issuer, 'email'), valueString(issuer, 'phone')].filter((value): value is string => value !== null).flatMap((value) => wrap(value)),
    '',
    `Receipt number: ${document.document_number}`,
    `Issue date: ${issuedDate}`,
    `Order number: ${valueString(financial, 'order_number') ?? ''}`,
    '',
    'CUSTOMER',
    ...wrap(valueString(customer, 'name') ?? 'Customer'),
    ...[valueString(customer, 'email'), valueString(customer, 'phone'), valueString(customer, 'delivery_address'), valueString(customer, 'postcode')].filter((value): value is string => value !== null).flatMap((value) => wrap(value)),
    '',
    'ITEMS'
  ];
  const items = Array.isArray(financial.items) ? financial.items : [];
  for (const rawItem of items) {
    if (!isRecord(rawItem)) continue;
    const name = valueString(rawItem, 'product_name') ?? 'Item';
    const portion = valueString(rawItem, 'portion_note');
    lines.push(...wrap(`${name}${portion ? ` — ${portion}` : ''}`));
    lines.push(`  ${valueNumber(rawItem, 'quantity')} x ${amount(valueNumber(rawItem, 'unit_price'), currency)} = ${amount(valueNumber(rawItem, 'line_subtotal'), currency)}`);
  }
  const taxAmount = valueNumber(financial, 'tax_amount');
  lines.push('', `Subtotal: ${amount(valueNumber(financial, 'subtotal'), currency)}`, `Delivery: ${amount(valueNumber(financial, 'delivery_fee'), currency)}`);
  const discount = valueNumber(financial, 'discount_amount');
  if (discount !== 0) lines.push(`Discount: ${amount(discount, currency)}`);
  if (taxAmount !== 0) lines.push(`${valueString(financial, 'tax_label') ?? 'Tax'}: ${amount(taxAmount, currency)}`);
  lines.push(`TOTAL: ${amount(valueNumber(financial, 'total'), currency)}`);
  const payment = isRecord(financial.payment) ? financial.payment : {};
  const reference = valueString(payment, 'provider_charge_id') ?? valueString(payment, 'provider_payment_intent_id');
  if (reference) lines.push('', ...wrap(`Payment reference: ${reference}`));

  const pages = Array.from({ length: Math.max(1, Math.ceil(lines.length / 46)) }, (_, index) => lines.slice(index * 46, (index + 1) * 46));
  const objects: string[] = ['<< /Type /Catalog /Pages 2 0 R >>', '', '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
  const pageObjectNumbers: number[] = [];
  for (const page of pages) {
    const pageNumber = objects.length + 1;
    const contentNumber = pageNumber + 1;
    pageObjectNumbers.push(pageNumber);
    const content = ['BT', '/F1 10 Tf', '50 790 Td', ...page.map((line, index) => `${index === 0 ? '' : '0 -15 Td\n'}(${pdfText(line)}) Tj`), 'ET'].join('\n');
    objects.push(`<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 3 0 R >> >> /MediaBox [0 0 612 842] /Contents ${contentNumber} 0 R >>`);
    objects.push(`<< /Length ${new TextEncoder().encode(content).length} >>\nstream\n${content}\nendstream`);
  }
  objects[1] = `<< /Type /Pages /Kids [${pageObjectNumbers.map((number) => `${number} 0 R`).join(' ')}] /Count ${pageObjectNumbers.length} >>`;
  let output = '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n';
  const offsets = [0];
  objects.forEach((object, index) => { offsets.push(new TextEncoder().encode(output).length); output += `${index + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = new TextEncoder().encode(output).length;
  output += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets.slice(1).map((offset) => `${String(offset).padStart(10, '0')} 00000 n `).join('\n')}\ntrailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(output);
}

Deno.serve(async (request) => {
  try {
    if (request.method === 'OPTIONS') return new Response('ok', { headers });
    if (request.method !== 'POST') return fail('method_not_allowed', 'Method not allowed.', 405);
  if (Number(request.headers.get('content-length') ?? 0) > MAX_REQUEST_BYTES) return fail('request_too_large', 'Request is too large.', 413);
  const authorization = request.headers.get('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  const url = Deno.env.get('SUPABASE_URL');
  const key = secretKey();
  if (!url || !key) { console.error('generate-receipt-pdf configuration is unavailable'); return fail('service_unavailable', 'Receipt generation is unavailable.', 503); }
  if (!token) return fail('unauthorized', 'Authentication is required.', 401);
  let body: unknown;
  try { body = await request.json(); } catch { return fail('invalid_request', 'A financial document ID is required.', 400); }
  if (!isRecord(body) || Object.keys(body).length !== 1 || typeof body.documentId !== 'string' || !uuidPattern.test(body.documentId)) return fail('invalid_request', 'A valid financial document ID is required.', 400);

  const admin = createClient(url, key);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData.user;
  if (userError || !user) return fail('unauthorized', 'Authentication is required.', 401);
  const { data: roleRows, error: roleError } = await admin.from('user_roles').select('role').eq('user_id', user.id);
  if (roleError || !Array.isArray(roleRows) || !roleRows.some((row) => row.role === 'owner' || row.role === 'manager')) return fail('forbidden', 'Owner or manager access is required.', 403);

  const { data: documentRow, error: documentError } = await admin
    .from('financial_documents')
    .select('id, document_type, document_number, issued_at, issuer_snapshot, customer_snapshot, financial_snapshot')
    .eq('id', body.documentId).maybeSingle();
  if (documentError) { console.error('generate-receipt-pdf document lookup failed'); return fail('receipt_lookup_failed', 'Could not load the receipt.', 503); }
  if (!documentRow) return fail('receipt_not_found', 'Receipt document was not found.', 404);
  if (documentRow.document_type !== 'receipt' || !isRecord(documentRow.issuer_snapshot) || !isRecord(documentRow.customer_snapshot) || !isRecord(documentRow.financial_snapshot)) return fail('invalid_receipt', 'Receipt document data is invalid.', 422);
  const receipt = documentRow as ReceiptDocument;
  const path = `receipts/${receipt.id}.pdf`;

  const { data: existingArtifact, error: artifactError } = await admin.from('financial_document_artifacts')
    .select('id, financial_document_id, storage_bucket, storage_object_path, mime_type, byte_size, sha256_hex, generator_version, generated_at')
    .eq('financial_document_id', receipt.id).eq('artifact_type', 'receipt_pdf').maybeSingle();
  if (artifactError) { console.error('generate-receipt-pdf artifact lookup failed'); return fail('artifact_lookup_failed', 'Could not load receipt artifact status.', 503); }
  if (existingArtifact) {
    const { data: objectFile, error: objectError } = await admin.storage.from(existingArtifact.storage_bucket).download(existingArtifact.storage_object_path);
    if (objectError || !objectFile) return fail('artifact_storage_missing', 'Receipt artifact metadata exists but its private file is missing. Resolve this before retrying.', 409);
    const objectBytes = new Uint8Array(await objectFile.arrayBuffer());
    const objectHash = await sha256Hex(objectBytes);
    if (!isValidReceiptPdf(objectBytes, receipt)
      || objectBytes.length !== Number(existingArtifact.byte_size)
      || objectHash !== existingArtifact.sha256_hex) {
      return fail('artifact_integrity_mismatch', 'Receipt artifact integrity verification failed. Resolve this before retrying.', 409);
    }
    const { data: signed, error: signedError } = await admin.storage.from(existingArtifact.storage_bucket).createSignedUrl(existingArtifact.storage_object_path, SIGNED_URL_TTL_SECONDS);
    if (signedError || !signed?.signedUrl) return fail('signed_url_failed', 'Could not prepare the receipt download.', 503);
    return new Response(JSON.stringify({ ok: true, artifact: existingArtifact as Artifact, signedUrl: signed.signedUrl, expiresIn: SIGNED_URL_TTL_SECONDS, generated: false }), { headers: { ...headers, 'Content-Type': 'application/json' } });
  }

  let bytes: Uint8Array;
  let renderedHash: string | null = null;
  let renderedByteSize: number | null = null;
  const { data: orphanFile, error: orphanError } = await admin.storage.from(BUCKET).download(path);
  if (!orphanError && orphanFile) {
    bytes = new Uint8Array(await orphanFile.arrayBuffer());
    if (!isValidReceiptPdf(bytes, receipt)) return fail('orphan_artifact_validation_failed', 'A private receipt object exists but does not match this receipt. Resolve it before retrying.', 409);
  }
  else {
    try { bytes = renderReceiptPdf(receipt); } catch { console.error('generate-receipt-pdf rendering failed'); return fail('render_failed', 'Could not render the receipt PDF.', 422); }
    if (!isValidReceiptPdf(bytes, receipt)) return fail('render_failed', 'Receipt PDF rendering failed validation.', 422);
    renderedHash = await sha256Hex(bytes);
    renderedByteSize = bytes.length;
    const { error: uploadError } = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: 'application/pdf', upsert: false });
    if (uploadError) {
      const { data: racedFile, error: racedError } = await admin.storage.from(BUCKET).download(path);
      if (racedError || !racedFile) return fail('storage_upload_failed', 'Could not store the receipt PDF.', 503);
      bytes = new Uint8Array(await racedFile.arrayBuffer());
      const racedHash = await sha256Hex(bytes);
      if (!isValidReceiptPdf(bytes, receipt) || racedHash !== renderedHash || bytes.length !== renderedByteSize) {
        return fail('artifact_concurrency_mismatch', 'A concurrent receipt PDF differs from this deterministic rendering. Resolve this before retrying.', 409);
      }
    }
  }
  if (!isValidReceiptPdf(bytes, receipt)) return fail('orphan_artifact_validation_failed', 'Receipt PDF validation failed before artifact registration.', 422);
  const hash = await sha256Hex(bytes);
  const { data: registered, error: registrationError } = await admin.rpc('register_receipt_pdf_artifact', {
    p_financial_document_id: receipt.id,
    p_storage_object_path: path,
    p_byte_size: bytes.length,
    p_sha256_hex: hash,
    p_generator_version: GENERATOR_VERSION,
    p_generated_by: user.id,
    p_generation_origin: 'authenticated_admin'
  });
  const artifact = Array.isArray(registered) ? registered[0] : registered;
  if (registrationError || !isRecord(artifact)) { console.error('generate-receipt-pdf artifact registration failed'); return fail('artifact_registration_failed', 'The PDF file exists but artifact registration failed; retry to recover it.', 409); }
  const { data: signed, error: signedError } = await admin.storage.from(BUCKET).createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
  if (signedError || !signed?.signedUrl) return fail('signed_url_failed', 'Receipt was generated but its download URL could not be prepared.', 503);
    return new Response(JSON.stringify({ ok: true, artifact, signedUrl: signed.signedUrl, expiresIn: SIGNED_URL_TTL_SECONDS, generated: true }), { headers: { ...headers, 'Content-Type': 'application/json' } });
  } catch {
    console.error('generate-receipt-pdf unexpected failure');
    return fail('internal_error', 'Receipt generation is unavailable.', 500);
  }
});
