# Firebase client key security

Updated: 2026-09-20

## Repository rule

Do not hardcode a Google/Firebase API key literal in Flutter source. The customer app reads `FIREBASE_API_KEY` from `String.fromEnvironment` and release workflows inject it with `--dart-define`.

Firebase client API keys are visible in a compiled client app by design. Treat the key as a client identifier that must be constrained and easy to rotate, not as a server credential.

Never put any of the following in Flutter or public Git history:

- Firebase service-account JSON
- service-account private keys
- Supabase service-role keys
- payment gateway server keys
- unrestricted server-side Google API credentials

## Rotation after public exposure

1. Create or select a replacement Firebase/Google client key in the project.
2. Apply the narrowest application and API restrictions compatible with the Android/iOS clients.
3. Add the replacement to GitHub Actions as repository secret `FIREBASE_API_KEY`.
4. Build and verify a release candidate with push messaging enabled.
5. Revoke the previously exposed key after the replacement is confirmed.
6. Close the GitHub secret-scanning alert as revoked/rotated only after the provider-side action is complete.

Removing a key from the latest source does not invalidate copies already present in public Git history. Provider-side rotation/revocation is mandatory after exposure.

## Local development

Pass the client key without writing it into source:

```bash
flutter run --dart-define=FIREBASE_API_KEY=YOUR_RESTRICTED_FIREBASE_CLIENT_KEY
```

For production, use the GitHub Actions secret rather than committing the value.
