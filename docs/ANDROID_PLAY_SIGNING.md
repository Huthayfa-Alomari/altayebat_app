# Android Play Signing — Altayebat

Updated: 2026-09-20

The Play Store release workflow is fail-closed. A release AAB cannot be built unless the permanent upload-key credentials are present.

## 1. Create the upload key locally

Run this on a trusted developer machine with a JDK installed. Never run it in CI and never commit the resulting JKS file.

### Windows PowerShell

```powershell
keytool -genkeypair -v `
  -keystore altayebat-upload.jks `
  -alias altayebat-upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

Keep the JKS and its passwords in a password manager / encrypted backup.

## 2. Encode the JKS for GitHub Actions

```powershell
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path ".\altayebat-upload.jks"))
[Convert]::ToBase64String($bytes) | Set-Clipboard
```

Add these GitHub Actions repository secrets:

- `ANDROID_RELEASE_KEYSTORE_BASE64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Do not place any of these values in source control, issues, pull requests, logs, or documentation.

## 3. Build the Play artifact

Run the `Android Play Release` workflow manually. It:

1. requires all four secrets,
2. reconstructs the JKS only inside the CI runner,
3. runs formatting, analysis, and tests,
4. builds a release AAB,
5. verifies the AAB signature with `jarsigner`,
6. publishes the AAB only as a workflow artifact.

## 4. Play App Signing

Enable Play App Signing in Google Play Console. Use the locally generated key as the upload key unless an existing Play Console configuration requires a different upload key.

## Recovery

Back up the upload key securely. If the upload key is lost, follow the Google Play upload-key reset process; do not create a second key and silently change CI.
