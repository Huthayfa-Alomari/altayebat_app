# Altayebat Supabase

This directory is the source of truth for the Supabase runtime used by the Flutter customer app and the Next.js admin dashboard.

## Database deployment order

This project predates a committed Supabase CLI migration history, so production hardening is kept as ordered, reviewable SQL layers. Apply them in this order against an existing compatible Altayebat schema:

1. `production_hardening.sql` — baseline RLS, authorization helpers and atomic checkout foundation.
2. `production_runtime_sync.sql` — production checkout contract, payment methods, delivery fee calculation, payment indexes and card finalization foundation.
3. `admin_rpc_hardening.sql` — moves privileged Admin analytics implementations into the non-exposed `private` schema while keeping stable public RPC wrappers.
4. `performance_hardening.sql` — RLS init-plan fixes, duplicate permissive-policy cleanup and missing foreign-key indexes.
5. `order_integrity_hardening.sql` — payment domain constraints, column-level order write privileges and gateway-managed card payment protection.
6. `order_status_hardening.sql` — transaction-safe order lifecycle state machine and inventory-safe cancellation.
7. `payment_reconciliation_hardening.sql` — late/duplicate PayTabs result handling, including `paid_requires_refund` when an authorised payment arrives after an order was already cancelled/restocked.

Later files intentionally tighten or supersede parts of earlier layers. Do not apply only a middle file to a fresh database and assume it represents the complete production contract.

The customer checkout RPC is:

```text
public.create_order(p_store_id, p_items, p_payment_method)
```

Supported payment methods are `cash`, `cliq`, and `card`.

Admin order lifecycle changes must use:

```text
public.admin_update_order_status(p_order_id, p_store_id, p_new_status)
```

Direct authenticated writes to `orders.status` are intentionally revoked so transition and inventory rules cannot be bypassed.

## Order lifecycle

Current lifecycle:

```text
pending -> preparing -> out_for_delivery -> delivered
   |           |
   +-> cancelled <-+
```

Rules:

- `delivered` and `cancelled` are terminal.
- Manual cancellation of card orders is blocked because card cancellation/failure is coupled to verified PayTabs state.
- A paid order cannot be silently cancelled/restocked; refund handling must happen first.
- Cancelling an eligible unpaid cash/CliQ order before dispatch restores inventory transactionally.
- `automation_order_status` is the production trigger responsible for status-history/notification writes when `orders.status` changes.

## Payment integrity

Payment methods and allowed states:

```text
cash -> unpaid | paid
cliq -> pending | paid | failed
card -> pending | paid | failed | refunded
```

For card payments:

- Browser/client code cannot mark a card order as paid.
- `payment_reference` is gateway-managed.
- PayTabs callback data is not trusted as proof by itself. The server queries PayTabs `/payment/query` and verifies `tran_ref` + `cart_id` before finalizing the order.
- `A` is treated as authorised/paid.
- terminal unsuccessful statuses handled by the integration include declined/error/expired/voided responses.
- Failed card payments while the order is still `pending` cancel the order and restore stock exactly once.
- Failure after fulfilment has advanced is recorded as `failed_requires_review` without changing inventory automatically.
- A late authorised result for an already cancelled/restocked order preserves the cancelled order, records the financial state as `paid`, and returns `paid_requires_refund` so the payment cannot be hidden.

## Abandoned card payments

PayTabs Hosted Payment Pages expire after 20 minutes. `reconcile-card-payment` uses a 25-minute safety window for orders where a payment page reference was never recorded. After that window, an eligible still-pending reservation can be finalized as failed and restocked.

Reconciliation is authenticated and may be requested only by:

- the customer who owns the order; or
- an admin assigned to that order's store.

If a PayTabs transaction reference exists, reconciliation queries PayTabs server-to-server before changing payment state.

## Edge Functions

Versioned functions:

- `create-card-payment` — authenticated customer endpoint that creates a PayTabs hosted payment page for the customer's card order.
- `reconcile-card-payment` — authenticated customer/admin endpoint that verifies or releases a pending card reservation safely.
- `paytabs-callback` — public PayTabs webhook; verifies the transaction server-to-server before finalization.
- `payment-return` — public browser return page after the customer leaves PayTabs.

JWT behavior is committed in `supabase/config.toml`:

- `create-card-payment`: JWT verification enabled.
- `reconcile-card-payment`: JWT verification enabled.
- `paytabs-callback`: JWT verification disabled because PayTabs calls it directly.
- `payment-return`: JWT verification disabled because the customer's browser returns to it directly.

## Required secrets

Never commit these values:

```text
PAYTABS_SERVER_KEY
PAYTABS_PROFILE_ID
```

Optional:

```text
PAYTABS_BASE_URL=https://secure-jordan.paytabs.com
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to hosted Edge Functions by Supabase. The service-role key must never be shipped in Flutter, Next.js client components, or any public bundle.

## Production release checklist

1. Confirm Anonymous Sign-ins remain enabled while the customer app uses anonymous Supabase Auth.
2. Apply the SQL layers above in the documented order.
3. Confirm the 3-argument `create_order` RPC and `admin_update_order_status` RPC exist.
4. Confirm `finalize_card_payment` is executable by `service_role` but not by `anon` or `authenticated`.
5. Confirm all four Edge Functions are deployed with the JWT settings in `config.toml`.
6. Confirm PayTabs secrets are configured in the Supabase project.
7. Run Supabase Security and Performance Advisors and review new warnings.
8. Test cash, CliQ, successful card payment, declined card payment, expired/abandoned payment reconciliation, duplicate callbacks and late-authorised/refund-review behavior.
9. Verify cancellation restores stock once and only once.
10. Verify Admin cannot change order totals, gateway references, card payment status, or order lifecycle state through direct table updates.
