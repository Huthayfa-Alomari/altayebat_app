$ErrorActionPreference = "Stop"

$Repo = "C:\Projects\altayebat_app"
$Flutter = Join-Path $Repo "altayebat_app"
$Package = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $Repo "_driver_deeplink_native_bridge_backup_$Stamp"

$Observer = Join-Path $Flutter "lib\services\driver_deep_link_navigator_observer.dart"
$MainActivity = Join-Path $Flutter "android\app\src\main\kotlin\com\altayebat\app\MainActivity.kt"

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required file not found: $Path"
    }
    $relative = $Path.Substring($Repo.Length).TrimStart('\')
    $target = Join-Path $Backup $relative
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath $Path -Destination $target -Force
}

function Restore-Backup {
    Write-Host ""
    Write-Host "Restoring backup..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $Backup) {
        Get-ChildItem -LiteralPath $Backup -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($Backup.Length).TrimStart('\')
            $target = Join-Path $Repo $relative
            $targetDir = Split-Path -Parent $target
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

try {
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null

    Backup-File $Observer
    Backup-File $MainActivity

    Write-Host "Installing native Android -> Flutter deep-link bridge..." -ForegroundColor Cyan
    Write-Host "Backup: $Backup"

    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\altayebat_app\lib\services\driver_deep_link_navigator_observer.dart") `
        -Destination $Observer -Force

    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\altayebat_app\android\app\src\main\kotlin\com\altayebat\app\MainActivity.kt") `
        -Destination $MainActivity -Force

    Push-Location $Flutter

    dart format `
        "lib\services\driver_deep_link_navigator_observer.dart"
    if ($LASTEXITCODE -ne 0) { throw "dart format failed" }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }

    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw "flutter debug APK build failed" }

    Pop-Location

    Write-Host ""
    Write-Host "Deep-link native bridge installed successfully." -ForegroundColor Green
    Write-Host "Next test with the connected phone:"
    Write-Host ""
    Write-Host '& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r ".\build\app\outputs\flutter-apk\app-debug.apk"'
    Write-Host ""
    Write-Host 'Then force-stop and open the driver deep link with ADB.'
    Write-Host "Backup: $Backup"
}
catch {
    Write-Host ""
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    try { Pop-Location -ErrorAction SilentlyContinue } catch {}
    Restore-Backup
    exit 1
}
