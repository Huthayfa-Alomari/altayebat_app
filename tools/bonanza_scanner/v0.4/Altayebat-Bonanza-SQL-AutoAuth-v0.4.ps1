param(
  [string]$OutputRoot = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Version = "0.4.0"
$Interesting = '(?i)(bonanza|gravity|inventory|stock|warehouse|pos|erp)'
$ConfigExt = '(?i)\.(config|ini|cfg|xml|json|txt|properties|settings)$'

function Invoke-SafeSelect {
  param([string]$ConnectionString,[string]$Query)
  if ($Query -notmatch '^\s*SELECT\b') { throw "Safety stop: SELECT only." }

  $cn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
  try {
    $cn.Open()
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = 20
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable
    [void]$da.Fill($dt)
    $rows = @()
    foreach ($row in $dt.Rows) {
      $o = [ordered]@{}
      foreach ($col in $dt.Columns) {
        $v = $row[$col.ColumnName]
        if ($v -is [System.DBNull]) { $v = $null }
        $o[$col.ColumnName] = $v
      }
      $rows += [pscustomobject]$o
    }
    return @($rows)
  }
  finally {
    if ($null -ne $cn) { $cn.Dispose() }
  }
}

function Get-SignalCategory {
  param([string]$Name)
  $n = $Name.ToLowerInvariant()
  if ($n -match 'barcode|bar_code|ean|upc|gtin') { return "barcode" }
  if ($n -match 'sku|itemcode|item_code|productcode|product_code|stockcode|stock_code|plu') { return "sku" }
  if ($n -match 'product|item|article|material|goods') { return "product" }
  if ($n -match 'price|sellprice|saleprice|retail|unitprice|unit_price') { return "price" }
  if ($n -match 'qty|quantity|stock|balance|onhand|on_hand|available') { return "stock" }
  if ($n -match 'warehouse|store|branch|location|depot') { return "warehouse" }
  if ($n -match 'image|photo|picture|pic|thumbnail|img') { return "image" }
  if ($n -match 'name|description|descr|title|arabic|english') { return "description" }
  return $null
}

function Get-CandidateRoots {
  $roots = New-Object System.Collections.Generic.List[string]

  foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    $path = $null
    try { $path = $p.Path } catch {}
    if ($p.ProcessName -match $Interesting -or ([string]$path) -match $Interesting) {
      if (-not [string]::IsNullOrWhiteSpace($path)) {
        $dir = Split-Path -Parent $path
        if (Test-Path -LiteralPath $dir) { $roots.Add($dir) }
      }
    }
  }

  $pf86 = [Environment]::GetFolderPath("ProgramFilesX86")
  foreach ($base in @($env:ProgramFiles,$pf86,$env:ProgramData,$env:LOCALAPPDATA,$env:APPDATA,"C:\")) {
    if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -Force -ErrorAction SilentlyContinue)) {
      if ($d.Name -match $Interesting) { $roots.Add($d.FullName) }
    }
  }

  return @($roots | Sort-Object -Unique)
}

function Get-ConfigFiles {
  param([string[]]$Roots)
  $files = New-Object System.Collections.Generic.List[object]

  foreach ($root in $Roots) {
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue([pscustomobject]@{Path=$root;Depth=0})
    $count = 0

    while ($queue.Count -gt 0 -and $count -lt 20000) {
      $node = $queue.Dequeue()
      foreach ($item in @(Get-ChildItem -LiteralPath $node.Path -Force -ErrorAction SilentlyContinue)) {
        if ($item.PSIsContainer) {
          if ($node.Depth -lt 4 -and $item.Name -notmatch '(?i)^(node_modules|\.git|temp|cache)$') {
            $queue.Enqueue([pscustomobject]@{Path=$item.FullName;Depth=$node.Depth+1})
          }
        } else {
          $count++
          if ($item.Name -match $ConfigExt -and $item.Length -le 2097152) {
            $files.Add($item)
          }
        }
      }
    }
  }

  return @($files | Sort-Object FullName -Unique)
}

function Get-ConnectionCandidates {
  param([object[]]$Files)

  $out = New-Object System.Collections.Generic.List[object]
  $seen = @{}

  foreach ($file in $Files) {
    $text = $null
    try { $text = [IO.File]::ReadAllText($file.FullName) } catch { continue }

    $matches = [regex]::Matches(
      $text,
      '(?is)(?:Data\s*Source|Server)\s*=\s*[^;"''\r\n<]+.*?(?:Initial\s*Catalog|Database)\s*=\s*[^;"''\r\n<]+.*?(?:User\s*ID|UID|UserName)\s*=\s*[^;"''\r\n<]+.*?(?:Password|Pwd)\s*=\s*[^;"''\r\n<]+(?:;|["''<\r\n])'
    )

    foreach ($m in $matches) {
      $raw = $m.Value.Trim()
      $raw = $raw.Trim('"',"'",'<','>',' ')
      if (-not $raw.EndsWith(";")) { $raw += ";" }

      try {
        $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($raw)
        $server = [string]$b.DataSource
        $db = [string]$b.InitialCatalog
        $user = [string]$b.UserID
        $pass = [string]$b.Password

        if ([string]::IsNullOrWhiteSpace($server) -or
            [string]::IsNullOrWhiteSpace($user) -or
            [string]::IsNullOrWhiteSpace($pass)) { continue }

        $key = ($server + "|" + $db + "|" + $user).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $b["Connect Timeout"] = 8
        $b["Encrypt"] = $false
        $b["TrustServerCertificate"] = $true
        $b["Application Name"] = "Altayebat Bonanza AutoAuth Scanner"
        try { $b["ApplicationIntent"] = "ReadOnly" } catch {}

        $out.Add([pscustomobject]@{
          SourcePath = $file.FullName
          Server = $server
          Database = $db
          User = $user
          Password = $pass
          ConnectionString = $b.ConnectionString
        })
      } catch {}
    }
  }

  return @($out)
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA SQL AUTOAUTH SCANNER v$Version" -ForegroundColor Green
Write-Host "Local credential discovery + READ-ONLY SQL metadata inspection." -ForegroundColor Yellow
Write-Host "Credentials are used in memory only and are NEVER written to the report." -ForegroundColor DarkGray
Write-Host "Only SELECT queries are permitted." -ForegroundColor DarkGray
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_AutoAuth_Scan_" + $stamp)
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host "[1/5] Locating Bonanza/Gravity folders..." -ForegroundColor Cyan
$roots = @(Get-CandidateRoots)
Write-Host ("Candidate roots: " + $roots.Count)

Write-Host "[2/5] Looking for local SQL connection configuration..." -ForegroundColor Cyan
$configFiles = @(Get-ConfigFiles -Roots $roots)
$candidates = @(Get-ConnectionCandidates -Files $configFiles)
Write-Host ("Config files checked: " + $configFiles.Count)
Write-Host ("SQL credential candidates found: " + $candidates.Count)

Write-Host "[3/5] Testing discovered credentials locally..." -ForegroundColor Cyan
$working = $null
$serverInfo = @()
$metadata = @()

foreach ($candidate in $candidates) {
  try {
    $serverInfo = Invoke-SafeSelect -ConnectionString $candidate.ConnectionString -Query @"
SELECT
  CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS server_name,
  CAST(SERVERPROPERTY('MachineName') AS nvarchar(256)) AS machine_name,
  CAST(SERVERPROPERTY('InstanceName') AS nvarchar(256)) AS instance_name,
  CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS product_version,
  CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS edition,
  DB_NAME() AS current_database;
"@

    $metadata = Invoke-SafeSelect -ConnectionString $candidate.ConnectionString -Query @"
SELECT
  s.name AS schema_name,
  t.name AS table_name,
  c.column_id,
  c.name AS column_name,
  ty.name AS data_type,
  c.max_length,
  c.precision,
  c.scale,
  c.is_nullable
FROM sys.tables AS t
INNER JOIN sys.schemas AS s ON s.schema_id = t.schema_id
INNER JOIN sys.columns AS c ON c.object_id = t.object_id
INNER JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;
"@

    $working = $candidate
    break
  } catch {}
}

if ($null -eq $working) {
  $report = [ordered]@{
    safety = [ordered]@{
      mode = "local_credential_discovery_only"
      credentials_exported = $false
      source_files_modified = $false
      sql_write_queries = $false
    }
    scanner_version = $Version
    scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    candidate_roots = $roots
    config_files_checked = @($configFiles | ForEach-Object { $_.FullName })
    credential_candidates_found = $candidates.Count
    sql_connection_success = $false
    next_step = "No usable plaintext SQL login was found. Use v0.3 with a dedicated read-only SQL login, or inspect Bonanza encrypted configuration."
  }

  $json = Join-Path $OutputRoot "bonanza_autoauth_report.json"
  $report | ConvertTo-Json -Depth 8 | Set-Content -Path $json -Encoding UTF8
  $zip = $OutputRoot + ".zip"
  Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zip -Force

  Write-Host ""
  Write-Host "No usable local SQL credential was found." -ForegroundColor Yellow
  Write-Host "No database changes were made." -ForegroundColor Green
  Write-Host "Upload this ZIP:" -ForegroundColor Yellow
  Write-Host $zip
  [void](Read-Host "Press Enter to close")
  exit 0
}

Write-Host "[4/5] Mapping likely Bonanza schema fields..." -ForegroundColor Cyan

$mappings = @()
foreach ($m in $metadata) {
  $category = Get-SignalCategory ([string]$m.column_name)
  if ($null -eq $category) { continue }
  $mappings += [ordered]@{
    category = $category
    schema = [string]$m.schema_name
    table = [string]$m.table_name
    column = [string]$m.column_name
    data_type = [string]$m.data_type
    nullable = [bool]$m.is_nullable
  }
}

$tables = @($metadata | Select-Object schema_name,table_name -Unique)

$report = [ordered]@{
  safety = [ordered]@{
    mode = "local_autoauth_read_only_metadata"
    credentials_exported = $false
    sql_username_exported = $false
    sql_password_exported = $false
    only_select_queries = $true
    source_files_modified = $false
  }
  scanner_version = $Version
  scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  sql_connection_success = $true
  credential_source_file = $working.SourcePath
  server = @($serverInfo)
  database = $working.Database
  table_count = $tables.Count
  column_count = $metadata.Count
  candidate_mappings = $mappings
  schema_metadata = $metadata
}

$jsonPath = Join-Path $OutputRoot "bonanza_autoauth_schema_report.json"
$summaryPath = Join-Path $OutputRoot "bonanza_autoauth_schema_summary.txt"
$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$summary = @(
  "ALTAYEBAT BONANZA SQL AUTOAUTH SCANNER v$Version",
  "",
  "SUCCESS",
  "- SQL connection succeeded using Bonanza local configuration",
  "- Credentials stayed in memory and were not exported",
  "- SELECT-only metadata inspection",
  "",
  "DATABASE",
  "- Server: $($serverInfo[0].server_name)",
  "- Database: $($working.Database)",
  "- Tables: $($tables.Count)",
  "- Columns: $($metadata.Count)",
  "",
  "CANDIDATE FIELD COUNTS"
)

foreach ($cat in @("product","sku","barcode","price","stock","warehouse","image","description")) {
  $count = @($mappings | Where-Object { $_.category -eq $cat }).Count
  $summary += "- $cat : $count"
}

$summary += ""
$summary += "Upload the generated ZIP to the Altayebat project chat."
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "[5/5] Creating report ZIP..." -ForegroundColor Cyan
$zipPath = $OutputRoot + ".zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
Write-Host "Credentials were not written to disk." -ForegroundColor Green
Write-Host "Upload this ZIP:" -ForegroundColor Yellow
Write-Host $zipPath -ForegroundColor Yellow
Write-Host ""
[void](Read-Host "Press Enter to close")
