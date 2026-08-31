# So Yummy Foods — Development Instructions

## Project

This is an existing production React + Vite website for So Yummy Foods.

The customer-facing website is already live.

The current project must be preserved while new functionality is added.

## Important

Before modifying the project:

1. Inspect the existing project structure.
2. Inspect package.json and existing dependencies.
3. Inspect the current routing.
4. Inspect the current customer-facing pages and components.
5. Inspect how products/menu items are currently represented.
6. Inspect the current cart and checkout implementation, if present.
7. Inspect existing API/backend integrations.
8. Inspect environment variable usage.
9. Identify existing styling/UI conventions.

Do not make major architectural changes before understanding the existing application.

## Current Technology

- React
- Vite
- Existing project styling system
- Vercel for deployment

Supabase is planned for the backend/database/authentication, but the existing implementation must be inspected before integrating it.

The payment provider has NOT been selected yet.

Possible future payment providers include Stripe or another provider suitable for the client's market.

Do not tightly couple the application to a payment provider before the client makes a decision.

## Customer Website

The existing customer-facing website is the priority.

Do not redesign, rewrite, or restructure working customer-facing functionality unless explicitly required.

Preserve the current design and behavior.

## Admin Dashboard

A secure admin dashboard will eventually be added to the existing React application.

Expected areas include:

- Dashboard
- Products/Menu
- Categories
- Orders
- Inventory
- Customers
- Invoices/Receipts
- Settings

The admin dashboard should live within the existing application unless the audit demonstrates a strong reason otherwise.

## Security Rules

The browser must never be treated as trusted.

Never expose:

- Supabase service-role/secret keys
- payment provider secret keys
- webhook secrets
- database credentials

Never put secrets in VITE_* environment variables.

Never trust client-provided:

- prices
- order totals
- payment status
- inventory
- user roles

Database authorization must be enforced server-side/database-side.

Frontend route protection is not sufficient security.

## Development Approach

Work incrementally.

Before implementing a significant feature:

1. Explain the proposed approach.
2. Identify affected files.
3. Identify potential risks.
4. Implement only the requested feature.
5. Run relevant tests/build/lint checks.
6. Report what changed.

Do not make unrelated refactors.

Do not introduce unnecessary dependencies.

Do not claim something was tested unless it was actually tested.

## Existing Code

Prefer the existing project's conventions over introducing a new architecture simply because it is preferred elsewhere.

Reuse existing components and dependencies where appropriate.

Do not replace working code without a clear reason.

## Production Safety

The current production website must remain functional.

Before making changes that could affect production behavior, identify the risk and explain it.

Never modify deployment secrets or production configuration without explicit instruction.