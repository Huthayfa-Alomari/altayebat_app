# Altayebat Supabase

This directory is the source of truth for the Supabase runtime used by the Flutter customer app and the admin dashboard.

## Database

The repository contains two reviewable SQL layers because the project predates a committed Supabase CLI migration history:

1. `production_hardening.sql` — baseline RLS, authorization helpers and atomic checkout hardening.
2. `production_runtime_sync.sql` — current production checkout/payment contract that was previously ahead of GitHub.

Apply them in that order after reviewing them against the target schema. `production_runtime_sync.sql` intentionally fails early when the expected production columns are missing rather than silently creating an incomplete schema.

The Flutter client calls:

```text
public.create_order(p_store_id, p_items, p_payment_method)
```

Supported payment methods are `cash`, `cliq`, and `card`.

## Edge Functions

Versioned functions:

- `create-card-payment` — authenticated customer endpoint that creates a PayTabs payment page for the customer's card order.
- `paytabs-callback` — public webhook endpoint. It does not trust the callback payload as payment proof; it queries PayTabs server-to-server before updating `orders.payment_status`.
- `payment-return` — public browser return page shown after the customer leaves PayTabs.

JWT behavior is committed in `supabase/config.toml`:

- `create-card-payment`: JWT verification enabled.
- `paytabs-callback`: JWT verification disabled because PayTabs calls it directly.
- `payment-return`: JWT verification disabled because the browser returns to it directly.

## Required secrets

Do not commit any of these values:

```text
PAYTABS_SERVER_KEY
PAYTABS_PROFILE_ID
```

Optional:

```text
PAYTABS_BASE_URL=https://secure-jordan.paytabs.com
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to hosted Edge Functions by Supabase. The service-role key must never be shipped in Flutter, Next.js client components, or any public bundle.

## Deployment checks

Before a production release:

1. Confirm Anonymous Sign-ins remain enabled while the customer app uses anonymous Supabase Auth.
2. Confirm the expected `create_order` 3-argument RPC exists.
3. Confirm all three Edge Functions are deployed with the JWT settings in `config.toml`.
4. Confirm PayTabs secrets are configured in the Supabase project.
5. Run Supabase Security and Performance Advisors and review new warnings before rollout.
6. Test cash, CliQ, successful card payment, declined card payment, and abandoned card payment flows.

## Important payment behavior

Inventory is currently decremented atomically when the order is created, before a card payment is completed. This protects against overselling, but abandoned/failed card payments require an operational cancellation/restock policy. Do not mark a card order as paid from the browser return page; payment state must come from the verified server-side callback path.
