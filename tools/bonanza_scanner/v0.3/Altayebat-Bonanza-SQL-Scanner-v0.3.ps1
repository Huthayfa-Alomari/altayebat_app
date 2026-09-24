param(
  [string]$Server = "localhost",
  [string]$OutputRoot = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScannerVersion = "0.3.0"

function ConvertTo-PlainText {
  param([System.Security.SecureString]$Secure)
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function New-SqlConnectionString {
  param(
    [string]$SqlServer,
    [string]$DatabaseName,
    [string]$UserName,
    [string]$Password
  )

  $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $builder["Data Source"] = $SqlServer
  $builder["Initial Catalog"] = $DatabaseName
  $builder["Integrated Security"] = $false
  $builder["User ID"] = $UserName
  $builder["Password"] = $Password
  $builder["Connect Timeout"] = 8
  $builder["Encrypt"] = $false
  $builder["TrustServerCertificate"] = $true
  $builder["Application Name"] = "Altayebat Bonanza SQL Scanner"
  $builder["ApplicationIntent"] = "ReadOnly"
  return $builder.ConnectionString
}

function Invoke-ReadOnlySelect {
  param(
    [string]$ConnectionString,
    [string]$Query
  )

  if ($Query -notmatch '^\s*SELECT\b') {
    throw "Safety stop: only SELECT statements are allowed."
  }

  $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
  try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = $Query
    $command.CommandTimeout = 20

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
    $table = New-Object System.Data.DataTable
    [void]$adapter.Fill($table)

    $rows = @()
    foreach ($row in $table.Rows) {
      $obj = [ordered]@{}
      foreach ($column in $table.Columns) {
        $value = $row[$column.ColumnName]
        if ($value -is [System.DBNull]) { $value = $null }
        $obj[$column.ColumnName] = $value
      }
      $rows += [pscustomobject]$obj
    }
    return @($rows)
  }
  finally {
    if ($null -ne $connection) { $connection.Dispose() }
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

function Get-DatabaseScore {
  param([object[]]$Metadata)
  $categories = @{}
  $tableSignals = 0

  foreach ($m in $Metadata) {
    $category = Get-SignalCategory ([string]$m.column_name)
    if ($null -ne $category) { $categories[$category] = $true }

    $tableName = ([string]$m.table_name).ToLowerInvariant()
    if ($tableName -match 'item|product|stock|inventory|warehouse|price|barcode|article|material') {
      $tableSignals++
    }
  }

  return [ordered]@{
    score = ($categories.Keys.Count * 10) + [Math]::Min($tableSignals, 25)
    categories = @($categories.Keys | Sort-Object)
    table_signal_count = $tableSignals
  }
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA SQL SCANNER v$ScannerVersion" -ForegroundColor Green
Write-Host "READ-ONLY SQL AUTHENTICATION MODE" -ForegroundColor Yellow
Write-Host "No password is written to disk or included in the report." -ForegroundColor DarkGray
Write-Host "Only SELECT statements are allowed." -ForegroundColor DarkGray
Write-Host ""

$userName = Read-Host "SQL read-only username"
$securePassword = Read-Host "SQL password" -AsSecureString
$password = ConvertTo-PlainText $securePassword

if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($password)) {
  Write-Host "Username/password cannot be empty." -ForegroundColor Red
  exit 2
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_SQL_Scan_v03_" + $stamp)
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$masterCs = New-SqlConnectionString -SqlServer $Server -DatabaseName "master" -UserName $userName -Password $password

Write-Host ""
Write-Host "[1/5] Testing read-only SQL login on $Server ..." -ForegroundColor Cyan

try {
  $serverInfo = Invoke-ReadOnlySelect -ConnectionString $masterCs -Query @"
SELECT
  CAST(SERVERPROPERTY('ServerName') AS nvarchar(256)) AS server_name,
  CAST(SERVERPROPERTY('MachineName') AS nvarchar(256)) AS machine_name,
  CAST(SERVERPROPERTY('InstanceName') AS nvarchar(256)) AS instance_name,
  CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS product_version,
  CAST(SERVERPROPERTY('ProductLevel') AS nvarchar(128)) AS product_level,
  CAST(SERVERPROPERTY('Edition') AS nvarchar(256)) AS edition;
"@
}
catch {
  $password = $null
  [GC]::Collect()

  Write-Host ""
  Write-Host "SQL login failed." -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "No database changes were made." -ForegroundColor Yellow
  Write-Host "Do NOT send the password. Send only a screenshot of this error."
  [void](Read-Host "Press Enter to close")
  exit 3
}

Write-Host "[2/5] Listing accessible user databases..." -ForegroundColor Cyan

$databases = Invoke-ReadOnlySelect -ConnectionString $masterCs -Query @"
SELECT
  name,
  database_id,
  state_desc,
  user_access_desc,
  recovery_model_desc,
  compatibility_level
FROM sys.databases
WHERE database_id > 4
  AND state_desc = 'ONLINE'
ORDER BY name;
"@

Write-Host ("Accessible user databases: " + $databases.Count)

$databaseReports = @()
$allMappings = @()

Write-Host "[3/5] Inspecting table and column metadata..." -ForegroundColor Cyan

foreach ($db in $databases) {
  $dbName = [string]$db.name
  Write-Host ("  - " + $dbName)

  $cs = New-SqlConnectionString -SqlServer $Server -DatabaseName $dbName -UserName $userName -Password $password

  try {
    $metadata = Invoke-ReadOnlySelect -ConnectionString $cs -Query @"
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

    $score = Get-DatabaseScore -Metadata $metadata

    foreach ($m in $metadata) {
      $category = Get-SignalCategory ([string]$m.column_name)
      if ($null -ne $category) {
        $allMappings += [ordered]@{
          database = $dbName
          category = $category
          schema = [string]$m.schema_name
          table = [string]$m.table_name
          column = [string]$m.column_name
          data_type = [string]$m.data_type
          nullable = [bool]$m.is_nullable
        }
      }
    }

    $databaseReports += [ordered]@{
      database = $dbName
      database_id = $db.database_id
      compatibility_level = $db.compatibility_level
      table_count = @($metadata | Select-Object schema_name, table_name -Unique).Count
      column_count = $metadata.Count
      candidate_score = $score.score
      detected_categories = $score.categories
      metadata = $metadata
    }
  }
  catch {
    $databaseReports += [ordered]@{
      database = $dbName
      error = $_.Exception.Message
    }
  }
}

$password = $null
[GC]::Collect()

Write-Host "[4/5] Ranking likely Bonanza database and fields..." -ForegroundColor Cyan

$ranking = @(
  $databaseReports |
    Where-Object { $_.Contains("candidate_score") } |
    Sort-Object candidate_score -Descending |
    Select-Object database, candidate_score, table_count, column_count, detected_categories
)

$report = [ordered]@{
  safety = [ordered]@{
    mode = "read_only_sql_metadata"
    authentication = "SQL Login"
    username = $userName
    password_saved = $false
    only_select_queries = $true
    application_intent = "ReadOnly"
    business_rows_exported = $false
    source_data_modified = $false
  }
  scanner_version = $ScannerVersion
  scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  requested_server = $Server
  server = @($serverInfo)
  accessible_databases = @($databases)
  ranking = $ranking
  candidate_mappings = @($allMappings)
  databases = $databaseReports
}

$jsonPath = Join-Path $OutputRoot "bonanza_sql_schema_report.json"
$summaryPath = Join-Path $OutputRoot "bonanza_sql_schema_summary.txt"

$report | ConvertTo-Json -Depth 14 | Set-Content -Path $jsonPath -Encoding UTF8

$summary = @(
  "ALTAYEBAT BONANZA SQL SCANNER v$ScannerVersion",
  "",
  "SAFETY",
  "- SQL Login authentication",
  "- Password is NOT saved",
  "- SELECT-only metadata inspection",
  "- No business rows exported",
  "- No INSERT / UPDATE / DELETE / EXEC",
  "",
  "SERVER"
)

if ($serverInfo.Count -gt 0) {
  $summary += "- Server: $($serverInfo[0].server_name)"
  $summary += "- Version: $($serverInfo[0].product_version)"
  $summary += "- Edition: $($serverInfo[0].edition)"
}

$summary += ""
$summary += "DATABASE RANKING"

foreach ($item in ($ranking | Select-Object -First 10)) {
  $cats = ($item.detected_categories -join ", ")
  $summary += "- $($item.database): score=$($item.candidate_score), tables=$($item.table_count), signals=[$cats]"
}

$summary += ""
$summary += "LIKELY INTEGRATION FIELDS"

foreach ($category in @("product","sku","barcode","price","stock","warehouse","image","description")) {
  $matches = @($allMappings | Where-Object { $_.category -eq $category } | Select-Object -First 20)
  if ($matches.Count -eq 0) { continue }

  $summary += ""
  $summary += ("[" + $category.ToUpperInvariant() + "]")
  foreach ($match in $matches) {
    $summary += "- $($match.database).$($match.schema).$($match.table).$($match.column) ($($match.data_type))"
  }
}

$summary += ""
$summary += "Upload the generated ZIP to the Altayebat project chat."
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "[5/5] Creating upload ZIP..." -ForegroundColor Cyan
$zipPath = $OutputRoot + ".zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Upload this ZIP:" -ForegroundColor Yellow
Write-Host $zipPath -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to close..."
[void](Read-Host)
