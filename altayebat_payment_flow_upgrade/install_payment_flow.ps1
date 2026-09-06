param(
  [string]$RepoRoot = "C:\Projects\altayebat_app"
)

$ErrorActionPreference = "Stop"
$PatchRoot = Join-Path $PSScriptRoot "patch"
$FlutterRoot = Join-Path $RepoRoot "altayebat_app"
$AdminRoot = Join-Path $RepoRoot "Admin"
$SupabaseRoot = Join-Path $RepoRoot "supabase"

if (-not (Test-Path $FlutterRoot)) {
  throw "Flutter app not found: $FlutterRoot"
}
if (-not (Test-Path $AdminRoot)) {
  throw "Admin app not found: $AdminRoot"
}
if (-not (Test-Path $SupabaseRoot)) {
  throw "Supabase folder not found: $SupabaseRoot"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupRoot = "C:\Projects\altayebat_backups\payment_flow_$stamp"
New-Item -ItemType Directory -Force $BackupRoot | Out-Null

$relativeFiles = @(
  "altayebat_app\lib\services\supabase_service.dart",
  "altayebat_app\lib\screens\delivery_checkout_screen.dart",
  "altayebat_app\lib\screens\order_tracking_screen.dart",
  "Admin\src\app\dashboard\settings\page.tsx",
  "supabase\20260906_payment_flow_hardening_v1.sql",
  "supabase\functions\payment-readiness\index.ts",
  "supabase\functions\create-card-payment\index.ts"
)

Write-Host ""
Write-Host "=== Altayebat Payment Flow Upgrade ===" -ForegroundColor Cyan
Write-Host "Repo:   $RepoRoot"
Write-Host "Backup: $BackupRoot"
Write-Host ""

foreach ($relative in $relativeFiles) {
  $source = Join-Path $PatchRoot $relative
  $target = Join-Path $RepoRoot $relative

  if (-not (Test-Path $source)) {
    throw "Patch file missing: $source"
  }

  if (Test-Path $target) {
    $backup = Join-Path $BackupRoot $relative
    $backupDir = Split-Path $backup -Parent
    New-Item -ItemType Directory -Force $backupDir | Out-Null
    Copy-Item $target $backup -Force
  }

  $targetDir = Split-Path $target -Parent
  New-Item -ItemType Directory -Force $targetDir | Out-Null
  Copy-Item $source $target -Force
  Write-Host "UPDATED: $relative" -ForegroundColor Green
}

Write-Host ""
Write-Host "Formatting Dart files..." -ForegroundColor Cyan
Push-Location $FlutterRoot
try {
  dart format `
    .\lib\services\supabase_service.dart `
    .\lib\screens\delivery_checkout_screen.dart `
    .\lib\screens\order_tracking_screen.dart

  if ($LASTEXITCODE -ne 0) {
    throw "dart format failed"
  }

  Write-Host ""
  Write-Host "Running flutter analyze..." -ForegroundColor Cyan
  flutter analyze
  if ($LASTEXITCODE -ne 0) {
    throw "flutter analyze failed"
  }

  Write-Host ""
  Write-Host "Running flutter test..." -ForegroundColor Cyan
  flutter test
  if ($LASTEXITCODE -ne 0) {
    throw "flutter test failed"
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "Building Admin..." -ForegroundColor Cyan
Push-Location $AdminRoot
try {
  npm run build
  if ($LASTEXITCODE -ne 0) {
    throw "Admin npm run build failed"
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
Write-Host "Backup: $BackupRoot"
Write-Host ""
Write-Host "Admin payment settings route:"
Write-Host "  /dashboard/settings"
Write-Host ""
Write-Host "Important:"
Write-Host "1) Add CliQ Alias + recipient + store phone from Admin /dashboard/settings."
Write-Host "2) PayTabs requires PAYTABS_SERVER_KEY and PAYTABS_PROFILE_ID in Supabase Edge Function Secrets."
Write-Host "3) Do NOT place PAYTABS_SERVER_KEY in Flutter, GitHub, or Vercel."
Write-Host "4) Backend migration/functions were already applied to the live Supabase project in this work session."
