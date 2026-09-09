# Altayebat Native Driver Mode v1 — Fixed Installer

This version fixes the installer conflict with the existing `MaterialApp.builder`.

Instead of replacing or wrapping `builder`, it registers a
`NavigatorObserver` that listens for:

`altayebat://driver?token=<secure-token>`

and opens the protected native Driver Mode screen.

The existing app `builder` remains untouched.

## Install

```powershell
cd C:\Projects\altayebat_app
Expand-Archive .\altayebat_native_driver_mode_v1_fixed.zip . -Force
powershell -ExecutionPolicy Bypass -File .\altayebat_native_driver_mode_v1_fixed\install_native_driver_mode_v1.ps1
```

The failed previous installer already restored its backup, so no manual cleanup
is required before running this fixed package.

The Production Supabase migration is already applied. Do not run its SQL
manually.
