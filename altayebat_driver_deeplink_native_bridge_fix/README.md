# Altayebat Driver Deep-Link Native Bridge Fix

Android is already resolving:

`altayebat://driver?...`

to `com.altayebat.app/.MainActivity`.

This patch fixes the remaining handoff inside Flutter by bypassing `app_links`
for Driver Mode and sending Android intents directly from `MainActivity` to
Dart over a `MethodChannel`.

It handles both:

- cold start (`getInitialLink`)
- app already open (`onNewIntent` -> `onDeepLink`)

The existing `MaterialApp.builder` and `navigatorObservers` integration remain
unchanged.

## Install

```powershell
cd C:\Projects\altayebat_app
Expand-Archive .\altayebat_driver_deeplink_native_bridge_fix.zip . -Force
powershell -ExecutionPolicy Bypass -File .\altayebat_driver_deeplink_native_bridge_fix\install.ps1
```

After success, install the newly built debug APK to the connected test phone:

```powershell
cd C:\Projects\altayebat_app\altayebat_app

& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r `
".\build\app\outputs\flutter-apk\app-debug.apk"
```

Then test:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" shell am force-stop com.altayebat.app

& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" shell am start `
-a android.intent.action.VIEW `
-d "altayebat://driver?token=<FRESH_TOKEN>"
```

Do not change AndroidManifest.xml; Android intent resolution was already
confirmed.
