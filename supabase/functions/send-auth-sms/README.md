# Altayebat custom OTP SMS hook

This Edge Function is the transport layer for Supabase Auth phone OTP.

Supabase remains responsible for:
- generating the OTP
- OTP expiry / rate limiting
- OTP verification
- creating the authenticated session

This function only sends the OTP through the configured SMS provider.

## Security

- Deploy with `verify_jwt = false` because the Auth hook runs before a user JWT exists.
- Requests are authenticated with Supabase Standard Webhooks signatures using `SEND_SMS_HOOK_SECRET`.
- The function never logs the OTP or the complete phone number.
- Do not enable the Send SMS Auth Hook until provider credentials are configured and tested.

## Required Edge Function secrets

- `SEND_SMS_HOOK_SECRET` — the secret generated for the Supabase Authentication > Hooks > Send SMS hook. Multiple secrets can be separated with `|` during rotation.
- `SMS_PROVIDER_URL` — provider REST endpoint.

## Recommended secrets

- `SMS_PROVIDER_API_KEY`
- `SMS_PROVIDER_AUTH_HEADER` — defaults to `Authorization`
- `SMS_PROVIDER_AUTH_SCHEME` — e.g. `Bearer`; leave empty for raw API key
- `SMS_SENDER_ID` — defaults to `Altayebat`
- `SMS_ALLOWED_PHONE_PREFIX` — use `+9627` for Jordanian mobile numbers
- `SMS_MESSAGE_TEMPLATE` — supports `{{otp}}`, `{{phone}}`, and `{{sender}}`

## Provider payload options

### Simple field mapping

Defaults:
- `SMS_FIELD_TO=to`
- `SMS_FIELD_MESSAGE=message`
- `SMS_FIELD_SENDER=sender`

### Custom JSON payload

Set `SMS_PROVIDER_PAYLOAD_TEMPLATE`, for example:

```json
{"mobile":"{{phone}}","text":"{{message}}","from":"{{sender}}"}
```

Nested JSON objects and arrays are supported.

### Additional headers

Use `SMS_PROVIDER_HEADERS_JSON`, for example:

```json
{"Accept":"application/json","X-Account":"altayebat"}
```

### Body format

- `SMS_PROVIDER_BODY_FORMAT=json` (default)
- `SMS_PROVIDER_BODY_FORMAT=form`
- `SMS_PROVIDER_BODY_FORMAT=query` for providers that expect query-string parameters

## Activation

1. Get the SMS provider API URL and credentials.
2. Configure the Edge Function secrets above.
3. In Supabase Dashboard open Authentication > Hooks.
4. Enable Send SMS and point it to this Edge Function.
5. Copy the generated hook secret into `SEND_SMS_HOOK_SECRET`.
6. Test with a real Jordanian number before production rollout.

Flutter should continue using the existing:
- `signInWithOtp(phone: ...)`
- `verifyOTP(...)`

No provider-specific code belongs in the mobile app.
