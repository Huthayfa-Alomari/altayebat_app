# Altayebat Release Readiness

Updated: 2026-09-20

## Production code and database status

- [x] Core Supabase schema is reproducible from Git. The baseline migration `20260822012530_initial_schema.sql` defines the original stores, categories, products, customers, addresses, drivers, orders, order_items, driver_locations, store_admins and call_requests tables.
- [x] Production migration drift is synchronized back into `supabase/migrations/`, including the GTIN bulk-import and account-deletion workflow migrations created on 2026-09-20.
- [x] Obsolete tracked backup/archive files and one-off driver patch packages are removed from source control. Root ZIP files and backup/patch scratch directories are ignored.
- [x] Smart Shopping Assistant is authenticated and rate-limited atomically in PostgreSQL before any OpenRouter/Groq request: 6 requests/minute and 60 requests/hour per customer. Limit responses use HTTP 429 and `Retry-After`.
- [x] AI assistant uses authenticated Supabase Edge Function access and only recommends live catalog products.
- [x] OpenRouter is the primary AI provider, Groq is the fallback, and deterministic catalog fallback remains available.
- [x] AI budget parsing distinguishes party-size numbers from budget/currency amounts and supports Arabic-Indic digits.
- [x] AI health endpoint requires an authenticated store admin.
- [x] Card/CliQ orders cannot be dispatched or delivered through rider or admin status flows unless payment is confirmed as `paid`.
- [x] Order status mutations flow through the hardened RPC state machine.
- [x] Offer campaigns, scheduled cancellation, loyalty rewards and free-delivery reward safety are present in production.
- [x] Delivery radius/address snapshot and rider workflow are present in production.
- [x] Android compile/target SDK is pinned to API 36.
- [x] Android release builds fail closed when permanent signing material is missing.
- [x] A dedicated `Android Play Release` workflow requires permanent upload-key secrets, runs quality checks, builds the AAB, and verifies its signature with `jarsigner`.
- [x] Public privacy-policy and account-deletion routes exist in the web application: `/privacy` and `/account-deletion`.
- [x] Google Play Data Safety mapping is documented in `docs/GOOGLE_PLAY_DATA_SAFETY.md`.
- [x] Admin GTIN/EAN CSV import is implemented with EAN-8 / UPC-A / EAN-13 / GTIN-14 checksum validation, duplicate checks, dry-run validation and fail-closed atomic application.
- [x] Performance cleanup removes the duplicate AI customer/time index and adds the missing account-deletion customer FK index.
- [x] No Firebase/Google API key literal is embedded in Flutter source; release builds receive `FIREBASE_API_KEY` through build-time configuration, and CI rejects credential-like literals in application source.

## External / operator-owned launch requirements

These items require private credentials, a third-party console action, or real source-of-truth product data. They must not be fabricated or committed to Git.

- [ ] Revoke/rotate the previously exposed Firebase/Google client API key in Google Cloud/Firebase, restrict the replacement key to the intended application/API surface, and add the replacement as GitHub Actions secret `FIREBASE_API_KEY`.
- [ ] Generate or select the permanent Google Play upload key, then configure these GitHub Actions secrets:
  - `ANDROID_RELEASE_KEYSTORE_BASE64`
  - `ANDROID_RELEASE_STORE_PASSWORD`
  - `ANDROID_RELEASE_KEY_ALIAS`
  - `ANDROID_RELEASE_KEY_PASSWORD`
  - Procedure: `docs/ANDROID_PLAY_SIGNING.md`
- [ ] Enable/confirm Play App Signing and run the `Android Play Release` workflow successfully with the permanent upload key.
- [ ] Verify the deployed public URLs for `/privacy` and `/account-deletion`, then enter them in Google Play Console.
- [ ] Complete the Google Play Data Safety form using `docs/GOOGLE_PLAY_DATA_SAFETY.md`, re-checking the answers against the exact production build.
- [ ] Import real GTIN/EAN values from packaging, supplier feeds, or the POS. Production currently has 683 products and 0 populated product barcodes. Never fabricate or infer GTIN values.
- [ ] Run one real in-app AI request after installing the latest release candidate and verify `ai_basket_requests.result.provider` is `openrouter:<model>` to prove the configured OpenRouter secret works upstream.
- [ ] Review/replace reused catalog images and fill optional content gaps (descriptions / English names) as merchandising polish.
- [ ] Confirm delivery zones and active rider capacity match the actual launch coverage.

## Known historical data note

A historical card order was found with `status = delivered` while `payment_status = pending`. Current admin and rider paths block that state from being created. The historical row remains unchanged because payment history must not be rewritten without gateway evidence.

## Release rule

Never publish a debug-signed or temporary-key AAB. Store publication requires the permanent upload key and a successful `Android Play Release` workflow. Real GTIN values must come from an authoritative product source.
