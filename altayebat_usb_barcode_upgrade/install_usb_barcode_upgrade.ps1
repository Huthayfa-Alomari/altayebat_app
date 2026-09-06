$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Target = Join-Path $ProjectRoot "Admin\src\app\dashboard\products\ProductsManager.tsx"
$Patch = Join-Path $PSScriptRoot "patch\Admin\src\app\dashboard\products\ProductsManager.tsx"

if (-not (Test-Path $Target)) {
    throw "ProductsManager.tsx was not found at: $Target"
}

$current = [System.IO.File]::ReadAllText($Target, [System.Text.Encoding]::UTF8)

if (-not $current.Contains('@/components/products/barcode-field')) {
    throw "Current ProductsManager does not contain the expected BarcodeField integration. Upgrade aborted to avoid overwriting an incompatible file."
}

if (-not $current.Contains('validateAdminBarcode')) {
    throw "Current ProductsManager does not contain validateAdminBarcode. Upgrade aborted to avoid overwriting an incompatible file."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupDir = Join-Path $ProjectRoot "_usb_barcode_backup_$timestamp"
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Copy-Item $Target (Join-Path $BackupDir "ProductsManager.tsx") -Force

Write-Host ""
Write-Host "Backup created: $BackupDir" -ForegroundColor Cyan
Write-Host "Installing USB barcode quick-scan upgrade..." -ForegroundColor Cyan

Copy-Item $Patch $Target -Force

Push-Location (Join-Path $ProjectRoot "Admin")
try {
    Write-Host ""
    Write-Host "Running Admin production build..." -ForegroundColor Cyan
    npm run build
    if ($LASTEXITCODE -ne 0) {
        throw "Admin build failed"
    }
}
catch {
    Write-Host ""
    Write-Host "Build failed. Restoring ProductsManager.tsx from backup..." -ForegroundColor Yellow
    Copy-Item (Join-Path $BackupDir "ProductsManager.tsx") $Target -Force
    throw
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "USB barcode upgrade installed successfully." -ForegroundColor Green
Write-Host "Next: test /dashboard/products, then git add/commit/push." -ForegroundColor Green
