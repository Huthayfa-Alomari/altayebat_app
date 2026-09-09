$ErrorActionPreference = "Stop"

$Repo = "C:\Projects\altayebat_app"
$Flutter = Join-Path $Repo "altayebat_app"
$Admin = Join-Path $Repo "Admin"
$Package = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $Repo "_native_driver_mode_backup_$Stamp"
$CreatedFiles = New-Object System.Collections.Generic.List[string]

function Copy-Backup([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $relative = $Path.Substring($Repo.Length).TrimStart('\')
        $target = Join-Path $Backup $relative
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        Copy-Item -LiteralPath $Path -Destination $target -Force
    } else {
        $CreatedFiles.Add($Path)
    }
}

function Restore-Backup {
    Write-Host ""
    Write-Host "Restoring backup..." -ForegroundColor Yellow

    foreach ($path in $CreatedFiles) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

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

function Insert-Import([string]$Content, [string]$ImportLine) {
    if ($Content.Contains($ImportLine)) { return $Content }

    $matches = [regex]::Matches($Content, '(?m)^import\s+.+?;\s*$')
    if ($matches.Count -eq 0) {
        throw "Could not locate Dart imports in main.dart"
    }
    $last = $matches[$matches.Count - 1]
    $pos = $last.Index + $last.Length
    return $Content.Insert($pos, "`r`n$ImportLine")
}

try {
    $Main = Join-Path $Flutter "lib\main.dart"
    $Pubspec = Join-Path $Flutter "pubspec.yaml"
    $Publock = Join-Path $Flutter "pubspec.lock"
    $Manifest = Join-Path $Flutter "android\app\src\main\AndroidManifest.xml"
    $DriverScreen = Join-Path $Flutter "lib\screens\driver_mode_screen.dart"
    $DriverService = Join-Path $Flutter "lib\services\driver_tracking_service.dart"
    $Observer = Join-Path $Flutter "lib\services\driver_deep_link_navigator_observer.dart"
    $DriverLayout = Join-Path $Admin "src\app\driver\layout.tsx"
    $SqlDst = Join-Path $Repo "supabase\20260909_driver_native_deeplink_v1.sql"

    foreach ($required in @($Main, $Pubspec, $Manifest)) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Required file missing: $required"
        }
    }

    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    foreach ($path in @(
        $Main, $Pubspec, $Publock, $Manifest,
        $DriverScreen, $DriverService, $Observer,
        $DriverLayout, $SqlDst
    )) {
        Copy-Backup $path
    }

    Write-Host "Installing native Driver Mode (fixed)..." -ForegroundColor Cyan
    Write-Host "Backup: $Backup"

    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\altayebat_app\lib\screens\driver_mode_screen.dart") `
        -Destination $DriverScreen -Force
    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\altayebat_app\lib\services\driver_tracking_service.dart") `
        -Destination $DriverService -Force
    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\altayebat_app\lib\services\driver_deep_link_navigator_observer.dart") `
        -Destination $Observer -Force

    Push-Location $Flutter

    $pub = Get-Content -LiteralPath $Pubspec -Raw
    if ($pub -notmatch '(?m)^\s*app_links\s*:') {
        Write-Host "Adding app_links dependency..."
        flutter pub add "app_links:^7.2.1"
        if ($LASTEXITCODE -ne 0) { throw "flutter pub add app_links failed" }
    }

    $pub = Get-Content -LiteralPath $Pubspec -Raw
    if ($pub -notmatch '(?m)^\s*url_launcher\s*:') {
        Write-Host "Adding url_launcher dependency..."
        flutter pub add url_launcher
        if ($LASTEXITCODE -ne 0) { throw "flutter pub add url_launcher failed" }
    }

    Pop-Location

    # main.dart integration:
    # Do NOT touch the project's existing MaterialApp builder.
    # Register a NavigatorObserver instead.
    $mainText = Get-Content -LiteralPath $Main -Raw
    $mainText = Insert-Import `
        $mainText `
        "import 'services/driver_deep_link_navigator_observer.dart';"

    if ($mainText -notmatch 'DriverDeepLinkNavigatorObserver\.instance') {
        $materialIndex = $mainText.IndexOf("MaterialApp(")
        if ($materialIndex -lt 0) {
            throw "main.dart does not contain MaterialApp(."
        }

        $scanLength = [Math]::Min(2000, $mainText.Length - $materialIndex)
        $materialHead = $mainText.Substring($materialIndex, $scanLength)

        if ($materialHead -match '(?m)^\s*navigatorObservers\s*:') {
            throw "MaterialApp already defines navigatorObservers. Automatic merge is unsafe."
        }

        $insertAt = $materialIndex + "MaterialApp(".Length
        $property = "`r`n        navigatorObservers: [`r`n          DriverDeepLinkNavigatorObserver.instance,`r`n        ],"
        $mainText = $mainText.Insert($insertAt, $property)
    }

    Set-Content -LiteralPath $Main -Value $mainText -Encoding UTF8

    # Android permissions + deep link.
    $manifestText = Get-Content -LiteralPath $Manifest -Raw

    $permissions = @(
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
    )

    foreach ($permission in $permissions) {
        if (-not $manifestText.Contains($permission)) {
            $manifestOpenEnd = $manifestText.IndexOf(">")
            if ($manifestOpenEnd -lt 0) { throw "Invalid AndroidManifest.xml" }
            $manifestText = $manifestText.Insert(
                $manifestOpenEnd + 1,
                "`r`n    $permission"
            )
        }
    }

    $activityMatch = [regex]::Match(
        $manifestText,
        '(?s)<activity\b[^>]*android:name="\.MainActivity"[^>]*>.*?</activity>'
    )
    if (-not $activityMatch.Success) {
        throw "Could not find .MainActivity in AndroidManifest.xml"
    }

    $activity = $activityMatch.Value

    if ($activity -match 'flutter_deeplinking_enabled') {
        $activity = [regex]::Replace(
            $activity,
            '<meta-data\s+android:name="flutter_deeplinking_enabled"\s+android:value="[^"]*"\s*/>',
            '<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />'
        )
    } else {
        $activity = $activity.Replace(
            "</activity>",
            "            <meta-data android:name=`"flutter_deeplinking_enabled`" android:value=`"false`" />`r`n        </activity>"
        )
    }

    if ($activity -notmatch 'android:scheme="altayebat"') {
        $filter = @"
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="altayebat" android:host="driver" />
            </intent-filter>
"@
        $activity = $activity.Replace(
            "</activity>",
            "$filter        </activity>"
        )
    }

    $manifestText = $manifestText.Remove(
        $activityMatch.Index,
        $activityMatch.Length
    ).Insert($activityMatch.Index, $activity)

    Set-Content -LiteralPath $Manifest -Value $manifestText -Encoding UTF8

    # Web fallback / native handoff.
    if (Test-Path -LiteralPath $DriverLayout) {
        $existingLayout = Get-Content -LiteralPath $DriverLayout -Raw
        if ($existingLayout -notmatch 'altayebat://driver') {
            throw "Admin driver/layout.tsx already exists. Automatic overwrite refused."
        }
    } else {
        Copy-Item `
            -LiteralPath (Join-Path $Package "patch\Admin\src\app\driver\layout.tsx") `
            -Destination $DriverLayout -Force
    }

    Copy-Item `
        -LiteralPath (Join-Path $Package "patch\supabase\20260909_driver_native_deeplink_v1.sql") `
        -Destination $SqlDst -Force

    Write-Host ""
    Write-Host "1/2 Flutter validation..." -ForegroundColor Cyan
    Push-Location $Flutter

    dart format `
        "lib\screens\driver_mode_screen.dart" `
        "lib\services\driver_tracking_service.dart" `
        "lib\services\driver_deep_link_navigator_observer.dart" `
        "lib\main.dart"
    if ($LASTEXITCODE -ne 0) { throw "dart format failed" }

    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }

    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw "flutter debug APK build failed" }

    Pop-Location

    Write-Host ""
    Write-Host "2/2 Admin production build..." -ForegroundColor Cyan
    Push-Location $Admin
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "Admin npm run build failed" }
    Pop-Location

    Write-Host ""
    Write-Host "Native Driver Mode installed successfully." -ForegroundColor Green
    Write-Host "Deep link: altayebat://driver?token=<secure-token>"
    Write-Host "Existing MaterialApp builder was preserved."
    Write-Host "Production Supabase migration is ALREADY applied. Do NOT run SQL manually."
    Write-Host "Backup: $Backup"
}
catch {
    Write-Host ""
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    try { Pop-Location -ErrorAction SilentlyContinue } catch {}
    Restore-Backup
    exit 1
}
