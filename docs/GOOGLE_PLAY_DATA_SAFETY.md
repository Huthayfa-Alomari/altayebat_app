# Google Play Data Safety — Altayebat

Updated: 2026-09-20

This is the operator checklist for the Google Play Data Safety form. Re-check it whenever SDKs or product behavior change.

## App data currently used

| Google Play category | Collected? | Purpose / notes |
|---|---:|---|
| Name | Yes | Customer profile, order fulfilment, payment handoff |
| Phone number | Yes | Account verification/contact, delivery, payment handoff |
| Precise / approximate location | Yes, when the user chooses location | Delivery address, reverse geocoding, serviceability and ETA |
| Purchase history | Yes | Orders, invoices, loyalty, support and reorder |
| App interactions | Yes | First-party analytics events and feature usage |
| Device or other IDs | Yes | Firebase Cloud Messaging registration token |
| User-generated text | Yes | Support input and AI shopping prompt when those features are used |
| Payment card details | No, not stored by Altayebat | Card entry and processing are handled by PayTabs |
| Photos/videos from barcode camera | No | Camera frames are processed for barcode scanning and are not uploaded by the scanner flow |

## Third-party processors / destinations

- Supabase: authentication, database, storage and Edge Functions.
- Firebase Cloud Messaging: push notification delivery.
- PayTabs: card payment processing; customer name/phone and transaction context are sent as needed.
- OpenStreetMap Nominatim: coordinates used for reverse geocoding.
- OSRM: route coordinates used for ETA/routing.
- OpenRouter / Groq: AI shopping prompt and a bounded live-catalog candidate list. The AI request does not include customer phone or delivery address.
- SMS/OTP provider: phone number and authentication message when a provider is enabled.

## Security / deletion

- Data is transmitted over HTTPS/TLS.
- Supabase RLS and authenticated RPCs restrict customer-data access.
- In-app account-deletion request: Account > Delete account and my data.
- Public deletion page: /account-deletion.
- Transaction/invoice records may need limited retention for legal or accounting obligations.

## Play Console submission checks

1. Confirm the production build contains the same SDKs and permissions documented here.
2. Classify service-provider processing according to Google's current "data sharing" definitions.
3. Confirm the public privacy-policy URL and public account-deletion URL are reachable without login.
4. Update this file if a new analytics, ads, payment, maps, AI, crash-reporting, or messaging SDK is added.
