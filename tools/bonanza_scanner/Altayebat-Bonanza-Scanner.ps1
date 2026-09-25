param(
  [string]$OutputRoot = "",
  [switch]$IncludeFileSamples
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$ScannerVersion = "0.1.0"
$Interesting = '(?i)(bonanza|gravity|inventory|stock|warehouse|pos|erp)'
$DbExt = '(?i)\.(mdf|ldf|mdb|accdb|sqlite|sqlite3|db|db3|sdf|fdb|gdb)$'
$ImgExt = '(?i)\.(jpg|jpeg|png|webp|bmp|gif|tif|tiff)$'
$CfgExt = '(?i)\.(ini|config|cfg|xml|json|yaml|yml|txt|properties)$'
$BackupExt = '(?i)\.(bak|backup|bkp|zip|7z|rar)$'

function Mask-Secrets {
  param([AllowNull()][string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

  $result = $Text
  $patterns = @(
    '(?im)(password\s*[:=]\s*)[^;\r\n]+',
    '(?im)(pwd\s*[:=]\s*)[^;\r\n]+',
    '(?im)(user\s*id\s*[:=]\s*)[^;\r\n]+',
    '(?im)(userid\s*[:=]\s*)[^;\r\n]+',
    '(?im)(uid\s*[:=]\s*)[^;\r\n]+',
    '(?im)(username\s*[:=]\s*)[^;\r\n]+',
    '(?im)("password"\s*:\s*")[^"]*(")',
    '(?im)("pwd"\s*:\s*")[^"]*(")'
  )

  foreach ($pattern in $patterns) {
    try {
      $result = [regex]::Replace($result, $pattern, {
        param($m)
        if ($m.Groups.Count -ge 3 -and $m.Groups[2].Success) {
          return $m.Groups[1].Value + "***REDACTED***" + $m.Groups[2].Value
        }
        return $m.Groups[1].Value + "***REDACTED***"
      })
    } catch {}
  }

  return $result
}

function Get-LimitedFiles {
  param(
    [string]$Root,
    [int]$MaxDepth = 5,
    [int]$MaxFiles = 30000
  )

  if (-not (Test-Path -LiteralPath $Root)) { return @() }

  $results = New-Object System.Collections.Generic.List[object]
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue([pscustomobject]@{ Path = $Root; Depth = 0 })

  while ($queue.Count -gt 0 -and $results.Count -lt $MaxFiles) {
    $node = $queue.Dequeue()
    $children = @(Get-ChildItem -LiteralPath $node.Path -Force -ErrorAction SilentlyContinue)

    foreach ($child in $children) {
      if ($results.Count -ge $MaxFiles) { break }

      if ($child.PSIsContainer) {
        if ($node.Depth -lt $MaxDepth -and $child.Name -notmatch '(?i)^(node_modules|\.git|Windows|WinSxS|System Volume Information|\$Recycle\.Bin)$') {
          $queue.Enqueue([pscustomobject]@{ Path = $child.FullName; Depth = $node.Depth + 1 })
        }
      } else {
        $results.Add($child)
      }
    }
  }

  return @($results)
}

function Get-CandidateDirectories {
  $roots = New-Object System.Collections.Generic.List[string]
  $pf86 = [Environment]::GetFolderPath("ProgramFilesX86")

  $known = @(
    "C:\Bonanza",
    "C:\Gravity",
    "C:\GravitySolutions",
    "C:\ProgramData\Bonanza",
    "C:\ProgramData\Gravity",
    "$env:ProgramFiles\Bonanza",
    "$env:ProgramFiles\Gravity",
    "$pf86\Bonanza",
    "$pf86\Gravity",
    "$env:LOCALAPPDATA\Bonanza",
    "$env:LOCALAPPDATA\Gravity",
    "$env:APPDATA\Bonanza",
    "$env:APPDATA\Gravity"
  )

  foreach ($path in $known) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
      $roots.Add((Resolve-Path -LiteralPath $path).Path)
    }
  }

  $parents = @($env:ProgramFiles, $pf86, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, "C:\") |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) }

  foreach ($parent in $parents) {
    $dirs = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue)
    foreach ($dir in $dirs) {
      if ($dir.Name -match $Interesting) { $roots.Add($dir.FullName) }

      if ($parent -ne "C:\" -and $dir.Name -notmatch '(?i)^(Windows|Microsoft|Packages|Temp)$') {
        foreach ($sub in @(Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
          if ($sub.Name -match $Interesting) { $roots.Add($sub.FullName) }
        }
      }
    }
  }

  return @($roots | Sort-Object -Unique)
}

function Get-InstalledApps {
  $paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )

  $out = New-Object System.Collections.Generic.List[object]
  foreach ($path in $paths) {
    foreach ($item in @(Get-ItemProperty $path -ErrorAction SilentlyContinue)) {
      $name = [string]$item.DisplayName
      $publisher = [string]$item.Publisher
      $location = [string]$item.InstallLocation

      if ($name -match $Interesting -or $publisher -match $Interesting -or $location -match $Interesting) {
        $out.Add([ordered]@{
          display_name = $name
          version = [string]$item.DisplayVersion
          publisher = $publisher
          install_location = $location
        })
      }
    }
  }
  return @($out | Sort-Object display_name, version -Unique)
}

function Get-RelevantProcesses {
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    $path = $null
    try { $path = $p.Path } catch {}
    if ($p.ProcessName -match $Interesting -or ([string]$path) -match $Interesting) {
      $out.Add([ordered]@{
        process_name = $p.ProcessName
        process_id = $p.Id
        executable_path = $path
      })
    }
  }
  return @($out)
}

function Get-DbServices {
  $pattern = '(?i)(mssql|sql server|sqlexpress|mysql|mariadb|postgres|firebird|interbase)'
  return @(
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match $pattern -or $_.DisplayName -match $pattern -or $_.PathName -match $pattern } |
      ForEach-Object {
        [ordered]@{
          name = $_.Name
          display_name = $_.DisplayName
          state = $_.State
          start_mode = $_.StartMode
          path_name = Mask-Secrets ([string]$_.PathName)
        }
      }
  )
}

function Get-SqlInstances {
  $locations = @(
    "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Microsoft SQL Server\Instance Names\SQL"
  )

  $out = New-Object System.Collections.Generic.List[object]
  foreach ($location in $locations) {
    if (-not (Test-Path $location)) { continue }
    $props = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
    if ($null -eq $props) { continue }

    foreach ($prop in $props.PSObject.Properties) {
      if ($prop.Name -notmatch '^PS') {
        $out.Add([ordered]@{
          instance_name = $prop.Name
          instance_id = [string]$prop.Value
        })
      }
    }
  }
  return @($out)
}

function Get-DbPorts {
  if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return @() }
  $ports = @(1433, 1434, 3050, 3306, 5432)
  return @(
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $ports -contains $_.LocalPort } |
      ForEach-Object {
        [ordered]@{
          local_address = $_.LocalAddress
          local_port = $_.LocalPort
          process_id = $_.OwningProcess
        }
      }
  )
}

function Get-Executables {
  param([string[]]$Roots)
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    foreach ($file in @(Get-LimitedFiles -Root $root -MaxDepth 4 -MaxFiles 15000)) {
      if ($file.Extension -ieq ".exe" -and ($file.Name -match $Interesting -or $file.DirectoryName -match $Interesting)) {
        try {
          $v = $file.VersionInfo
          $out.Add([ordered]@{
            path = $file.FullName
            file_name = $file.Name
            size_bytes = $file.Length
            product_name = $v.ProductName
            product_version = $v.ProductVersion
            file_version = $v.FileVersion
            company_name = $v.CompanyName
          })
        } catch {}
      }
    }
  }

  return @($out | Sort-Object path -Unique)
}

function Get-DbFiles {
  param([string[]]$Roots)
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    foreach ($file in @(Get-LimitedFiles -Root $root -MaxDepth 6 -MaxFiles 50000)) {
      if ($file.Name -match $DbExt) {
        $out.Add([ordered]@{
          path = $file.FullName
          extension = $file.Extension
          size_bytes = $file.Length
          last_write_utc = $file.LastWriteTimeUtc.ToString("o")
        })
      }
    }
  }

  return @($out | Sort-Object path -Unique)
}

function Get-ConfigClues {
  param([string[]]$Roots)
  $clue = '(?i)(data\s*source|server\s*=|initial\s+catalog|database\s*=|db(name|path)?\s*=|provider\s*=|attachdbfilename|host\s*=|port\s*=|firebird|sqlexpress|mssql|mysql|postgres|sqlite|\.mdf|\.fdb|\.mdb|\.accdb|\.sqlite)'
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    foreach ($file in @(Get-LimitedFiles -Root $root -MaxDepth 5 -MaxFiles 25000)) {
      if ($file.Name -notmatch $CfgExt -or $file.Length -gt 1048576) { continue }

      try { $text = [IO.File]::ReadAllText($file.FullName) } catch { continue }
      if ($text -notmatch $clue) { continue }

      $safe = Mask-Secrets $text
      $lines = New-Object System.Collections.Generic.List[string]
      foreach ($line in ($safe -split '\r?\n')) {
        if ($line -match $clue) {
          $trimmed = $line.Trim()
          if (-not [string]::IsNullOrWhiteSpace($trimmed)) { $lines.Add($trimmed) }
        }
        if ($lines.Count -ge 30) { break }
      }

      if ($lines.Count -gt 0) {
        $out.Add([ordered]@{
          path = $file.FullName
          clues = @($lines)
        })
      }
    }
  }

  return @($out | Sort-Object path -Unique)
}

function Get-ImageFolders {
  param([string[]]$Roots)
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    $images = @(Get-LimitedFiles -Root $root -MaxDepth 6 -MaxFiles 50000 | Where-Object { $_.Name -match $ImgExt })
    foreach ($group in ($images | Group-Object DirectoryName | Sort-Object Count -Descending | Select-Object -First 30)) {
      $samples = @()
      if ($IncludeFileSamples) {
        $samples = @($group.Group | Select-Object -First 20 | ForEach-Object { $_.Name })
      }
      $out.Add([ordered]@{
        directory = $group.Name
        image_count = $group.Count
        sample_names = $samples
      })
    }
  }

  return @($out | Sort-Object directory -Unique)
}

function Get-Backups {
  param([string[]]$Roots)
  $out = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    foreach ($file in @(Get-LimitedFiles -Root $root -MaxDepth 5 -MaxFiles 25000)) {
      if ($file.Name -match $BackupExt -and ($file.Name -match $Interesting -or $file.DirectoryName -match '(?i)(backup|bak|bonanza|gravity)')) {
        $out.Add([ordered]@{
          path = $file.FullName
          size_bytes = $file.Length
          last_write_utc = $file.LastWriteTimeUtc.ToString("o")
        })
      }
    }
  }

  return @($out | Sort-Object path -Unique)
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA SCANNER v$ScannerVersion" -ForegroundColor Green
Write-Host "Read-only discovery: no DB queries, no registry/service changes." -ForegroundColor DarkGray
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_Scan_" + $stamp)
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host "[1/8] Detecting Bonanza / Gravity..." -ForegroundColor Cyan
$roots = @(Get-CandidateDirectories)
$apps = @(Get-InstalledApps)
$processes = @(Get-RelevantProcesses)
$executables = @(Get-Executables -Roots $roots)

Write-Host "[2/8] Detecting database engines..." -ForegroundColor Cyan
$services = @(Get-DbServices)
$sqlInstances = @(Get-SqlInstances)
$dbPorts = @(Get-DbPorts)

Write-Host "[3/8] Finding database files..." -ForegroundColor Cyan
$dbFiles = @(Get-DbFiles -Roots $roots)

Write-Host "[4/8] Reading sanitized configuration clues..." -ForegroundColor Cyan
$configClues = @(Get-ConfigClues -Roots $roots)

Write-Host "[5/8] Locating product image folders..." -ForegroundColor Cyan
$imageFolders = @(Get-ImageFolders -Roots $roots)

Write-Host "[6/8] Locating backup candidates..." -ForegroundColor Cyan
$backups = @(Get-Backups -Roots $roots)

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$system = [ordered]@{
  scanner_version = $ScannerVersion
  scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  computer_name = $env:COMPUTERNAME
  windows_caption = [string]$os.Caption
  windows_version = [string]$os.Version
  powershell_version = $PSVersionTable.PSVersion.ToString()
}

$signals = [ordered]@{
  candidate_directories = $roots.Count
  installed_app_matches = $apps.Count
  executable_matches = $executables.Count
  database_services = $services.Count
  sql_server_instances = $sqlInstances.Count
  database_files = $dbFiles.Count
  config_files_with_database_clues = $configClues.Count
  image_directories = $imageFolders.Count
  backup_candidates = $backups.Count
}

$recommendations = New-Object System.Collections.Generic.List[string]
if ($sqlInstances.Count -gt 0 -or @($services | Where-Object { $_.name -match '(?i)(mssql|sql)' }).Count -gt 0) {
  $recommendations.Add("SQL Server detected: build a read-only SQL adapter next.")
}
if (@($dbFiles | Where-Object { $_.extension -match '(?i)\.(fdb|gdb)' }).Count -gt 0) {
  $recommendations.Add("Firebird database file detected: build a read-only Firebird adapter next.")
}
if (@($dbFiles | Where-Object { $_.extension -match '(?i)\.(mdb|accdb)' }).Count -gt 0) {
  $recommendations.Add("Access database detected: inspect table names read-only next.")
}
if (@($dbFiles | Where-Object { $_.extension -match '(?i)\.(sqlite|sqlite3|db|db3)' }).Count -gt 0) {
  $recommendations.Add("SQLite-style database detected: inspect a copied database schema offline next.")
}
if ($imageFolders.Count -gt 0) {
  $recommendations.Add("Image folders detected: correlate filenames/paths with barcode or item ID.")
}
if ($recommendations.Count -eq 0) {
  $recommendations.Add("No clear database signal found in standard locations: use Bonanza export/backup or run a targeted second scan.")
}

Write-Host "[7/8] Writing reports..." -ForegroundColor Cyan

$report = [ordered]@{
  safety = [ordered]@{
    mode = "read_only_discovery"
    database_connections_opened = $false
    database_queries_executed = $false
    source_files_modified = $false
    registry_modified = $false
    services_modified = $false
    secrets_redacted = $true
  }
  system = $system
  signals = $signals
  candidate_directories = $roots
  installed_applications = $apps
  relevant_processes = $processes
  executable_candidates = $executables
  database = [ordered]@{
    services = $services
    sql_server_instances = $sqlInstances
    listening_ports = $dbPorts
    database_files = $dbFiles
    config_clues = $configClues
  }
  images = $imageFolders
  backups = $backups
  recommendations = @($recommendations)
}

$jsonPath = Join-Path $OutputRoot "bonanza_scan_report.json"
$summaryPath = Join-Path $OutputRoot "bonanza_scan_summary.txt"
$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$summary = @(
  "ALTAYEBAT BONANZA SCANNER v$ScannerVersion",
  "",
  "SAFETY",
  "- Read-only discovery",
  "- No database connection/query",
  "- No source file/registry/service changes",
  "- Common credentials are redacted",
  "",
  "DISCOVERY",
  "- Candidate directories: $($roots.Count)",
  "- Installed app matches: $($apps.Count)",
  "- Executable matches: $($executables.Count)",
  "- Database services: $($services.Count)",
  "- SQL Server instances: $($sqlInstances.Count)",
  "- Database files: $($dbFiles.Count)",
  "- Config clues: $($configClues.Count)",
  "- Image directories: $($imageFolders.Count)",
  "- Backup candidates: $($backups.Count)",
  "",
  "NEXT STEP"
)
foreach ($r in $recommendations) { $summary += "- $r" }
$summary += ""
$summary += "Upload the generated ZIP to the Altayebat project chat."
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "[8/8] Creating ZIP..." -ForegroundColor Cyan
$zipPath = $OutputRoot + ".zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Upload this file:" -ForegroundColor Yellow
Write-Host $zipPath -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to close..."
[void](Read-Host)
