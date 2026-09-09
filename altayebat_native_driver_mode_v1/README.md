# Altayebat Native Driver Mode v1

Moves driver GPS tracking from browser-only tracking into the Android Flutter
app while keeping `/driver?token=...` as a web fallback.

## Security

- Customer Mode remains the default.
- Driver Mode is not added to normal customer navigation.
- It opens only from `altayebat://driver?token=<secure-token>`.
- The token is checked by the existing Supabase driver RPCs.
- Invalid, expired, or revoked tokens cannot open a delivery task.

## Native GPS

- Uses `geolocator` from the installed Flutter app.
- Android active tracking uses a foreground location service notification.
- High accuracy, 5 meter distance filter, and a requested 5 second interval.
- No `ACCESS_BACKGROUND_LOCATION` permission is added in this version.
- GPS starts only when the driver explicitly starts/enables tracking.

## Web fallback

The existing `/driver?token=...` page remains. On a phone it attempts to open
the same token inside the installed app and also shows an explicit
"فتح المهمة في تطبيق أسواق الطيبات" button.

## Production backend

`driver_native_deeplink_v1` has already been applied to Production. It extends
`admin_issue_driver_tracking_session` with:

- `app_uri`
- `web_path`

Do **not** run the SQL manually against Production.

## Install

```powershell
cd C:\Projects\altayebat_app
Expand-Archive .\altayebat_native_driver_mode_v1.zip . -Force
powershell -ExecutionPolicy Bypass -File .\altayebat_native_driver_mode_v1\install_native_driver_mode_v1.ps1
```

The installer creates a timestamped backup, patches Flutter/Android/Admin,
then runs:

- `dart format`
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- Admin `npm run build`

If validation fails, it restores the touched source files automatically.

iOS deep-link registration is intentionally deferred until the iOS build is
tested on macOS/Xcode.
