# AGENTS.md — So Yummy Foods

## 1. Project Overview

So Yummy Foods is a production React website for a food business.

The project currently contains:
- A customer-facing website
- Menu browsing
- Shopping cart
- Checkout UI
- Media/blog/allergy pages
- Local/static menu data

The project is being extended with a secure admin/backend system using Supabase.

### Core stack

- React 18
- TypeScript
- Vite
- React Router
- Tailwind CSS
- Zustand
- Zod
- Supabase
- Supabase Auth
- Supabase PostgreSQL
- Supabase Storage
- Supabase Edge Functions / RPC where privileged server-side logic is required

Do not migrate the project to Next.js, another framework, or another backend architecture unless explicitly instructed.

---

# 2. Critical Development Rules

## Preserve the existing customer website

The existing customer-facing website is already working.

When implementing backend/admin functionality:

- Do not unnecessarily redesign existing customer pages.
- Do not replace working components without a clear reason.
- Do not modify unrelated customer functionality.
- Do not change existing visual styling unless specifically requested.
- Do not break existing routes.
- Do not change the existing menu/cart UX unless the current task requires it.
- Preserve existing responsive behavior.
- Preserve existing customer-facing URLs.

Customer-facing routes currently include:

- `/`
- `/menu`
- `/media`
- `/blog`
- `/allergy`

Admin routes must remain isolated under:

- `/admin/login`
- `/admin/...`

---

# 3. Work Incrementally

This project is being implemented in phases.

## Current implementation phases

### Phase 1 — Admin authentication
- Supabase project setup
- Admin authentication
- Profiles
- Admin roles
- RLS
- Protected admin routes
- Admin shell/dashboard

### Phase 2 — Products, categories and images
- Categories
- Products
- Product images
- Public menu read layer
- Admin product/category/image management

### Phase 3 — Delivery configuration
- Delivery zones
- Delivery fees
- Business settings

### Phase 4 — Inventory
- Sellable-item inventory
- Reservations
- Inventory movements
- Overselling protection

### Phase 5 — Guest orders
- Server-authoritative order creation
- Price calculation
- Delivery-zone calculation
- Stock reservation
- Idempotency
- Payment-pending lifecycle

### Phase 6 — Admin order management
- Order viewing
- Operational status changes
- Order history
- Staff/manager workflows

### Phase 7 — Payments
- Card payment integration
- Bank transfer workflow
- Webhook verification
- Payment reconciliation
- Payment idempotency

### Phase 8 — Financial documents
- Receipts
- Invoices when required
- Private document storage
- Signed access

### Future phases
- Promotions/discount management
- Refunds
- Post-payment financial adjustments
- Credit notes
- More advanced delivery functionality

## Do not skip phases

Do not implement future phases simply because they are architecturally possible.

If a task would require changing an earlier architectural decision, stop and explain the conflict before proceeding.

Do not expand scope without explicit instruction.

---

# 4. Current Architecture

The application uses a React/Vite frontend.

Supabase is the backend/data platform.

Use a small data/repository layer between UI components and Supabase wherever practical.

The UI should not contain business-critical database logic.

### Principle

The browser is untrusted.

Anything involving:

- prices
- totals
- discounts
- stock
- inventory reservations
- delivery fees
- order creation
- payment status
- payment verification
- staff permissions
- role management
- financial documents

must be authoritative on the server/database side.

Never trust values supplied by the browser for these operations.

---

# 5. Supabase Security Rules

## Browser credentials

The browser may contain only:

- Supabase project URL
- Supabase publishable/anon key

Never put any of the following in client-side code:

- Supabase service-role key
- payment secret key
- webhook signing secret
- private API credentials
- database passwords
- other privileged secrets

Never use `VITE_` environment variables for secrets.

---

# 6. Authentication

Admin authentication uses Supabase Auth.

There are no customer accounts in V1.

Customers use guest checkout.

Public signup for admin accounts must remain disabled.

Admins are created through the controlled admin workflow.

Admin roles:

- `owner`
- `manager`
- `staff`

Role management is owner-only.

Frontend route guards are for UX only.

Security must be enforced using PostgreSQL/RLS and trusted server-side operations.

Never assume hiding a button or route is a security control.

---

# 7. Database Security / RLS

Row Level Security must be enabled on all exposed application tables where appropriate.

Never disable RLS merely to make a query work.

If privileged access is necessary, use an appropriate server-side function/RPC or controlled service-role operation.

Security-definer functions must:

- use a fixed `search_path`
- avoid unsafe dynamic SQL
- avoid leaking protected data
- avoid recursive RLS evaluation

The `has_role()`/role helper pattern intentionally bypasses caller RLS where necessary to avoid recursive policy evaluation.

Do not remove this protection without understanding the security implications.

---

# 8. Database Schema Principles

The approved V1 schema is:

1. `profiles`
2. `user_roles`
3. `categories`
4. `products`
5. `product_images`
6. `inventory`
7. `inventory_movements`
8. `delivery_zones`
9. `orders`
10. `order_items`
11. `order_status_history`
12. `payments`
13. `payment_provider_events`
14. `financial_documents`
15. `business_settings`
16. `audit_logs`

Do not introduce additional tables merely for convenience.

If a new table appears necessary, explain why and get approval before adding it.

---

# 9. Historical Data Must Be Preserved

Orders, payments, inventory movements and financial documents are historical records.

Do not design destructive relationships that can silently remove historical information.

Important principles:

- Product deletion must not destroy historical order items.
- Orders must not be cascade-deleted.
- Payments must not be cascade-deleted.
- Inventory movement history must not be deleted because a product changes.
- Financial documents must remain historically meaningful.
- Order items store product/name/price/etc. snapshots.

Use appropriate foreign-key actions such as `RESTRICT`, `SET NULL`, or `CASCADE` only where explicitly appropriate.

---

# 10. Products

Products are the authoritative source for menu items.

A product contains information such as:

- category
- slug
- name
- description
- base price
- sale price
- currency
- price-on-request flag
- portion note
- preparation time
- status
- availability
- tags
- display order

Product lifecycle:

- `draft`
- `active`
- `archived`

`is_available` is a separate manual staff decision.

Do not equate availability with inventory.

A product can be manually unavailable even if stock exists.

A product can also be manually available while inventory is zero; checkout must still enforce inventory rules where inventory tracking is enabled.

---

# 11. Inventory

Inventory tracks sellable portions/menu items.

Do NOT introduce raw ingredient inventory, recipes, BOMs, suppliers, purchasing or warehouse management in V1.

Inventory contains concepts such as:

- quantity on hand
- quantity reserved
- low-stock threshold
- whether inventory is tracked

Available quantity is effectively:

`quantity_on_hand - quantity_reserved`

Inventory operations must be transactional.

When reserving stock:

1. Lock the relevant inventory row.
2. Recalculate current available stock.
3. Verify sufficient stock.
4. Increase reserved quantity.
5. Record an inventory movement.
6. Make the operation idempotent where necessary.

Never rely on frontend stock checks to prevent overselling.

---

# 12. Inventory Movement Ledger

`inventory_movements` is an immutable history.

Movement types include concepts such as:

- opening balance
- adjustment
- order reservation
- reservation release
- fulfilment
- return

Do not edit historical movement records to "correct" history.

Create a new compensating movement when appropriate.

Use idempotency keys for automated movements associated with orders/events.

---

# 13. Delivery

Delivery pricing is zone-based.

Do NOT introduce a global hard-coded delivery fee.

There is no permanent default such as `£3.50`.

Delivery zones contain:

- postcode prefixes
- delivery fee
- optional minimum order amount
- active state
- ordering/matching priority

The server must:

1. Normalize the postcode.
2. Find active matching zones.
3. Prefer the longest matching postcode prefix.
4. Then use `match_priority`.
5. Use a deterministic final tie-breaker if required.
6. Reject delivery checkout if no valid zone exists.

Collection can remain available even if delivery cannot be matched.

The actual delivery amount and zone name charged to an order must be snapshotted on the order.

Never recalculate historical order delivery charges from the current delivery-zone table.

---

# 14. Orders

Orders are authoritative operational and financial records.

Customers are guests in V1.

The browser may submit:

- product IDs
- quantities
- customer contact details
- fulfilment type
- delivery address where applicable
- notes
- discount code if eventually supported

The server must determine:

- product validity
- product availability
- current prices
- discounts
- delivery zone
- delivery fee
- tax where configured
- stock availability
- subtotal
- total

Never trust client-submitted totals.

---

# 15. Order Snapshots

Order history must remain accurate even if products or settings later change.

Order items must snapshot information such as:

- product ID where available
- product name
- slug
- portion information
- unit price
- discount
- line total

Orders must snapshot relevant:

- customer details
- contact details
- delivery address
- fulfilment type
- delivery zone name
- delivery amount
- subtotal
- discount
- tax
- total
- currency

Historical snapshots are the source of truth for the completed order.

---

# 16. Payment Lifecycle

Order flow:

1. Customer submits order.
2. Server validates the request.
3. Server calculates totals.
4. Server reserves stock.
5. Order is created as `pending_payment`.
6. Payment is attempted.
7. Payment is independently verified.
8. Successful payment changes the order to `confirmed`.
9. Business prepares the order.

Possible order lifecycle states include:

- `pending_payment`
- `confirmed`
- `preparing`
- `ready`
- `out_for_delivery`
- `completed`
- `cancelled`
- `payment_expired`

A pending payment must have a reservation deadline.

Expired pending payments must release their stock reservations.

Late payment events must be handled safely and must not silently revive or duplicate an expired order.

---

# 17. Payment Security

Payment provider webhooks must be:

- verified server-side
- idempotent
- stored/reconciled appropriately
- safe against duplicate delivery

Never trust a frontend "payment successful" callback as final proof of payment.

The authoritative payment status comes from verified server-side/provider evidence.

Do not store card numbers, CVVs, or other sensitive card data.

Payment provider secrets must remain server-side.

---

# 18. Payment Methods

V1 supports:

- Card
- Bank Transfer

The payment model represents payment attempts.

Do not add unnecessary concepts such as `payment_kind`.

Refunds and post-payment adjustments are intentionally deferred.

Do not model refunds as negative payment rows.

A future adjustment/refund ledger will be introduced when that functionality is implemented.

---

# 19. Post-Payment Order Editing

Once payment has been confirmed, the original financial snapshot is locked.

Do not silently overwrite:

- order items
- quantities
- product prices
- discounts
- subtotal
- delivery fee
- tax
- total
- fulfilment type
- customer/contact snapshot
- delivery address
- delivery zone snapshot

Safe operational changes may include:

- preparation status
- fulfilment status
- internal notes
- kitchen notes
- delivery assignment/time/window if later implemented

Financial changes require a controlled adjustment/refund workflow.

Do not implement an informal "edit paid order" mechanism.

---

# 20. Discounts

V1 only needs provision for discounts.

Orders may contain:

- `discount_amount`
- `discount_code_snapshot`

Do not build a complex promotion engine yet.

If discount functionality is implemented:

- validate codes server-side
- calculate discounts server-side
- never trust client-submitted discount amounts

Promotion tables and advanced campaign logic are deferred.

---

# 21. Financial Documents

Financial documents are immutable historical records.

V1 supports:

- receipts
- invoices when required/requested

A receipt is normally generated after verified payment.

Do not assume the business is VAT registered.

Do not add VAT wording, rates or tax-registration details unless explicitly configured.

Tax configuration is disabled by default.

Financial documents should snapshot the relevant:

- business identity
- order
- customer
- pricing
- tax
- payment
- document number

PDF documents should be stored privately.

Access should use authorized signed URLs or an equivalent controlled mechanism.

Do not expose private financial-document storage publicly.

---

# 22. Audit Logs

High-risk admin actions should be auditable.

Examples:

- role changes
- product changes
- inventory adjustments
- delivery-zone changes
- order status changes
- payment reconciliation actions
- financial document actions

Do not store:

- passwords
- service-role keys
- payment secrets
- full card information
- unnecessary webhook payloads
- unnecessary sensitive personal information

---

# 23. Admin Roles

### Owner

Full administrative access, including:

- user/role management
- products
- categories
- inventory
- delivery configuration
- orders
- payment/reconciliation controls
- business settings
- financial documents
- audit logs

### Manager

Operational/business management access including:

- products
- categories
- inventory
- delivery zones
- orders
- permitted payment/reconciliation actions

No owner-only role management.

### Staff

Operational access primarily for:

- viewing orders required for fulfilment
- customer information required to fulfil orders
- updating allowed order statuses
- operational notes
- limited unpaid-order edits where explicitly allowed

Staff must not manage roles, system settings or privileged financial operations.

---

# 24. Guest Checkout Security

Guests must not receive direct database access to:

- other orders
- inventory
- payments
- financial documents
- admin data
- customer records

Guest order creation must happen through a narrowly scoped trusted operation such as an Edge Function/RPC.

The guest request must be validated server-side.

Do not solve guest checkout security by granting broad anonymous `INSERT`/`SELECT` access to the orders table.

---

# 25. Supabase Storage

Public product/menu images may use controlled public storage where appropriate.

Financial documents must use private storage.

Do not make invoice/receipt storage public.

Use signed URLs or controlled server-side access for private documents.

---

# 26. Environment Variables

Use `.env.example` to document required configuration.

Never commit real secrets.

The repository must not contain:

- `.env`
- `.env.local`
- service-role keys
- payment secrets
- webhook secrets

Environment variables exposed to Vite client code must be treated as public.

Only variables intentionally safe for the browser may use the `VITE_` prefix.

---

# 27. Code Quality

Use TypeScript properly.

Avoid:

- unnecessary `any`
- duplicated business logic
- giant components
- hidden side effects
- magic constants for business rules
- hard-coded financial values
- hard-coded delivery prices
- duplicated Supabase queries throughout UI components

Prefer:

- small focused modules
- typed interfaces
- reusable repository/data functions
- explicit error handling
- schema validation
- clear naming
- predictable state management

Run the project's existing checks before considering a phase complete.

At minimum, when applicable:

- `npm run build`
- `npm run lint`
- `git diff --check`

Do not introduce unrelated lint/build changes.

---

# 28. Database Migrations

All schema changes must be made through migrations.

Do not manually modify the production database as a substitute for a migration.

Migrations should be:

- deterministic
- reviewable
- safe to apply
- explicit about constraints
- explicit about RLS/policies
- explicit about indexes where required

Never silently modify an existing migration that may already have been applied.

Create a new migration for subsequent changes.

---

# 29. Testing

Security-sensitive database changes must have corresponding verification tests where practical.

Especially test:

- anonymous access
- owner access
- manager access
- staff access
- self-role escalation
- profile protected fields
- RLS policies
- inventory overselling
- duplicate order creation
- duplicate webhook events
- payment expiry
- invalid delivery zones
- server-side total calculation

A frontend test passing does not prove that RLS/security is correct.

---

# 30. Repository/Data Layer

Do not couple every UI component directly to Supabase.

Where practical, use repository/data functions such as:

- menu repository
- product repository
- category repository
- order service
- inventory service

The existing customer-facing menu API/data shape should remain compatible where possible.

If the backend implementation changes from static data to Supabase, adapt the data layer rather than unnecessarily rewriting every menu component.

---

# 31. Error Handling

Do not expose internal database errors, secrets or implementation details to customers.

Customer-facing errors should be understandable.

Admin errors should provide enough context to diagnose the problem without exposing secrets.

Never log:

- passwords
- tokens
- service-role keys
- payment secrets
- card data

---

# 32. Do Not Over-Engineer V1

The following are intentionally OUT OF SCOPE unless explicitly requested:

- customer accounts
- loyalty programs
- CRM
- newsletter management
- raw ingredient inventory
- recipes/BOM
- supplier management
- purchasing
- warehouse management
- complex catering management
- advanced promotion engines
- geocoding/maps
- automated route optimization
- sophisticated delivery dispatch
- refunds/credit-note workflows
- complex accounting
- multi-currency support
- multi-branch architecture

Do not add these simply because they might be useful in the future.

Design current tables so future expansion is possible without prematurely implementing it.

---

# 33. Decision-Making Rule

When requirements are ambiguous:

1. Check this document.
2. Check the current database/schema and existing implementation.
3. Preserve existing behavior.
4. Prefer the simplest solution consistent with the approved architecture.
5. Do not invent new business rules.
6. Ask for clarification before making a decision that changes architecture, security, financial behavior or customer-facing behavior.

Never make assumptions about:

- tax/VAT
- delivery pricing
- payment provider
- refund policy
- cancellation policy
- customer account requirements
- catering workflows

unless explicitly specified.

---

# 34. Before Making Changes

Before implementing a task:

- Inspect the relevant existing files.
- Understand the current implementation.
- Identify dependencies.
- Check whether a migration already exists.
- Check existing RLS policies before adding new ones.
- Check whether the functionality belongs to the current phase.

Do not blindly generate new files when an existing abstraction should be extended.

---

# 35. After Making Changes

Before reporting completion:

1. Review the diff.
2. Check for accidental changes outside scope.
3. Run build/lint checks where applicable.
4. Run database/security verification where applicable.
5. Confirm no secrets were introduced.
6. Confirm RLS remains enabled and appropriate.
7. Confirm existing customer routes still work.
8. Summarize exactly what changed.
9. Clearly state anything that could not be tested because Supabase/project configuration is not yet available.

---

# 36. Current Project Status

Phase 1 admin authentication has been implemented.

Current known files/components include:

- `src/lib/supabase.ts`
- `src/types/admin.ts`
- `AdminAuthProvider.tsx`
- `AdminAuthContext.ts`
- `RequireAdmin.tsx`
- `AdminLayout.tsx`
- admin `Login.tsx`
- admin `Dashboard.tsx`
- `src/App.tsx`
- `src/index.tsx`
- `supabase/migrations/20260904120000_phase_1_admin_auth.sql`
- `supabase/tests/phase_1_rls_verification.sql`

Phase 1 verification already completed:

- `npm run build` passes
- `npm run lint` passes with one pre-existing Fast Refresh warning in `src/components/ui/button.tsx`
- `git diff --check` passes

The RLS verification script exists but requires an actual Supabase project, applied migration and test users before it can be executed against the real database.

Do not start Phase 2 automatically.

The next intended step is:

1. Create/configure the actual Supabase project.
2. Apply the Phase 1 migration.
3. Bootstrap the first owner.
4. Test admin authentication and RLS.
5. Only then begin Phase 2.

---

# 37. Important Instruction

Do not treat this file as permission to implement every feature described above.

This document defines the approved architecture and constraints.

Implement only the task explicitly requested.

If a requested change conflicts with this architecture, explain the conflict before changing the architecture.

When in doubt about a security, financial, database, or architectural decision:

STOP AND ASK.