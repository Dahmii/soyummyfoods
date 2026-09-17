# Phase 8D deployed runtime smoke

Run this only after the Phase 8D migration and `generate-receipt-pdf` Edge
Function are deployed. Use a disposable, already-issued receipt and an admin
session; do not use a customer or production order for destructive testing.

1. Sign in as a manager or owner and open the corresponding admin order. The
   Receipt section must show only when a Phase 8C receipt exists.
2. Select **Generate receipt PDF**. Confirm the returned file is a non-empty
   PDF containing the receipt number, issued date, order number, immutable
   item lines, totals, and payment reference. It must not contain capabilities,
   hashes, webhook payloads, or Stripe secrets. In a disposable fixture, use a
   long unbroken customer email, product token, address, and enough items to
   force a second page; each field must wrap within the printable width and
   totals must follow the item rows without overlap.
3. Repeat the action. Confirm the same canonical artifact remains in
   `financial_document_artifacts`, its SHA-256 and object path are unchanged,
   and no second artifact/audit row appears.
4. In Storage, verify `financial-documents` is private and the object path is
   `receipts/{financial_document_id}.pdf`. A signed URL must work briefly;
   the unsigned object URL must not work.
5. Verify the stored object byte count and SHA-256 match the artifact metadata.
   Replace the object only in a disposable environment and confirm generation
   returns `artifact_integrity_mismatch` without issuing a signed URL. Confirm
   the `financial_documents` row has not changed.
6. Sign in as staff and attempt the Edge Function request with a valid receipt
   document ID. Expect `403 forbidden`. Repeat without a JWT and expect `401`.
   Attempt direct Storage read/upload and direct artifact-table writes as anon
   and authenticated; all must be denied.
7. Temporarily simulate only in a disposable environment: delete the object
   while keeping metadata. Generation must return `artifact_storage_missing`.
   Create a valid generated PDF at the canonical path without metadata, then
   retry; the function must hash and register that exact object rather than
   overwrite it. A non-PDF object, or a PDF whose receipt/order markers belong
   to another document, must return `orphan_artifact_validation_failed` and
   must not create metadata.
8. Call `register_receipt_pdf_artifact` twice as the trusted service context
   with identical metadata and confirm it returns the same artifact. Repeat
   with a different hash, byte size, or path and confirm it fails with the
   canonical-metadata conflict invariant. During two simultaneous first
   generation requests, confirm one object and one artifact row exist; if the
   rendered bytes differ, the losing request must fail closed.

The Edge Function deliberately leaves a private orphan object visible for
recovery if Storage upload succeeds and DB registration fails. Retrying the
same request hashes and registers that object. Metadata with a missing object
is treated as an explicit repair condition, never silently regenerated.
