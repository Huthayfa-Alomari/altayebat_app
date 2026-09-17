# Altayebat Release Readiness

Updated: 2026-09-17

## Production code status

- [x] `main` contains the current customer, admin, rider, offers, loyalty, delivery, payment and AI work.
- [x] AI shopping assistant is exposed from the customer app main navigation.
- [x] AI assistant uses authenticated Supabase Edge Function access and only recommends live catalog products.
- [x] OpenRouter is the primary AI provider, Groq is the fallback, and deterministic catalog fallback remains available.
- [x] AI budget parsing distinguishes party-size numbers from budget/currency amounts and supports Arabic-Indic digits.
- [x] AI health endpoint requires an authenticated store admin.
- [x] Card/CliQ orders cannot be dispatched or delivered through rider or admin status flows unless payment is confirmed as `paid`.
- [x] Order status mutations flow through the hardened RPC state machine.
- [x] Offer campaigns, scheduled cancellation, loyalty rewards and free-delivery reward safety are present in production.
- [x] Delivery radius/address snapshot and rider workflow are present in production.
- [x] Performance cleanup applied for driver approval lookup and app-event RLS auth evaluation.
- [x] Android compile/target SDK is pinned to API 36 for current Google Play submission requirements.
- [x] CI quality checks cover Flutter format/analyze/test, customer Android builds, SUNMI builds, and admin typecheck/build/audit.
- [x] Release workflow builds and verifies APK and Play Store AAB artifacts.

## External / operator-owned launch requirements

- [ ] Configure a permanent Android production signing key / Play App Signing credentials in GitHub Actions. Do **not** publish a build signed by the temporary release-candidate key.
  - `ANDROID_RELEASE_KEYSTORE_BASE64`
  - `ANDROID_RELEASE_STORE_PASSWORD`
  - `ANDROID_RELEASE_KEY_ALIAS`
  - `ANDROID_RELEASE_KEY_PASSWORD`
- [ ] Publish a public privacy-policy URL and complete Google Play Data Safety declarations for the app's customer/order/location/notification data usage.
- [ ] Run one real in-app AI request after installing the latest app and verify `ai_basket_requests.result.provider` is `openrouter:<model>` to prove the newly configured OpenRouter secret works upstream.
- [ ] Import real GTIN/EAN barcodes from packaging, supplier feeds, or the POS. Never fabricate barcodes. The scanner cannot provide useful product lookup until real barcode data exists.
- [ ] Review/replace reused catalog images and fill optional content gaps (descriptions / English names) as merchandising polish.
- [ ] Confirm delivery zones and active rider capacity match the actual launch coverage.

## Known historical data note

A historical card order was found with `status = delivered` while `payment_status = pending`. Current admin and rider paths now block that state from being created. The historical row was deliberately left unchanged because payment history must not be rewritten without gateway evidence.

## Release rule

A release candidate generated with the workflow fallback key is for installation/testing only. Store publication requires the permanent production signing credentials above.
