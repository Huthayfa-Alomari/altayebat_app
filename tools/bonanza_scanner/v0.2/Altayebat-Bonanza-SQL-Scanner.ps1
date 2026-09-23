param(
  [string]$Server = "localhost",
  [string]$OutputRoot = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScannerVersion = "0.2.0"

function New-ReadOnlyConnectionString {
  param(
    [string]$SqlServer,
    [string]$DatabaseName
  )

  $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
  $builder["Data Source"] = $SqlServer
  $builder["Initial Catalog"] = $DatabaseName
  $builder["Integrated Security"] = $true
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
    if ($null -ne $connection) {
      $connection.Dispose()
    }
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
    if ($null -ne $category) {
      $categories[$category] = $true
    }

    $tableName = ([string]$m.table_name).ToLowerInvariant()
    if ($tableName -match 'item|product|stock|inventory|warehouse|price|barcode|article|material') {
      $tableSignals++
    }
  }

  $score = ($categories.Keys.Count * 10) + [Math]::Min($tableSignals, 25)

  return [ordered]@{
    score = $score
    categories = @($categories.Keys | Sort-Object)
    table_signal_count = $tableSignals
  }
}

function Get-CandidateMappings {
  param([object[]]$Metadata)

  $out = @()
  foreach ($m in $Metadata) {
    $category = Get-SignalCategory ([string]$m.column_name)
    if ($null -eq $category) { continue }

    $out += [ordered]@{
      category = $category
      schema = [string]$m.schema_name
      table = [string]$m.table_name
      column = [string]$m.column_name
      data_type = [string]$m.data_type
      nullable = [bool]$m.is_nullable
    }
  }

  return @($out)
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA SQL SCANNER v$ScannerVersion" -ForegroundColor Green
Write-Host "READ-ONLY METADATA MODE" -ForegroundColor Yellow
Write-Host "Only SELECT queries against SQL Server system catalogs are used." -ForegroundColor DarkGray
Write-Host "No INSERT / UPDATE / DELETE / EXEC is performed." -ForegroundColor DarkGray
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_SQL_Scan_" + $stamp)
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$masterConnectionString = New-ReadOnlyConnectionString -SqlServer $Server -DatabaseName "master"

Write-Host "[1/5] Connecting read-only to SQL Server: $Server" -ForegroundColor Cyan

try {
  $serverInfo = Invoke-ReadOnlySelect -ConnectionString $masterConnectionString -Query @"
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
  Write-Host ""
  Write-Host "Could not connect using Windows Integrated Authentication." -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  Write-Host ""
  Write-Host "No database changes were made." -ForegroundColor Yellow
  Write-Host "Take a screenshot of this window and send it to the Altayebat project chat."
  Write-Host ""
  [void](Read-Host "Press Enter to close")
  exit 2
}

Write-Host "[2/5] Listing accessible user databases..." -ForegroundColor Cyan

$databases = Invoke-ReadOnlySelect -ConnectionString $masterConnectionString -Query @"
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

Write-Host "[3/5] Inspecting table/column metadata only..." -ForegroundColor Cyan

foreach ($db in $databases) {
  $dbName = [string]$db.name
  Write-Host ("  - " + $dbName)

  $connectionString = New-ReadOnlyConnectionString -SqlServer $Server -DatabaseName $dbName

  try {
    $metadata = Invoke-ReadOnlySelect -ConnectionString $connectionString -Query @"
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
    $mappings = Get-CandidateMappings -Metadata $metadata

    foreach ($mapping in $mappings) {
      $allMappings += [ordered]@{
        database = $dbName
        category = $mapping.category
        schema = $mapping.schema
        table = $mapping.table
        column = $mapping.column
        data_type = $mapping.data_type
        nullable = $mapping.nullable
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

Write-Host "[4/5] Ranking likely Bonanza databases and integration fields..." -ForegroundColor Cyan

$ranking = @(
  $databaseReports |
    Where-Object { $_.Contains("candidate_score") } |
    Sort-Object candidate_score -Descending |
    Select-Object database, candidate_score, table_count, column_count, detected_categories
)

$report = [ordered]@{
  safety = [ordered]@{
    mode = "read_only_sql_metadata"
    authentication = "Windows Integrated Security"
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

$summary = @()
$summary += "ALTAYEBAT BONANZA SQL SCANNER v$ScannerVersion"
$summary += ""
$summary += "SAFETY"
$summary += "- Read-only SQL metadata inspection"
$summary += "- Windows Integrated Authentication"
$summary += "- SELECT statements only"
$summary += "- No business rows exported"
$summary += "- No INSERT / UPDATE / DELETE / EXEC"
$summary += ""
$summary += "SERVER"
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

foreach ($category in @("product", "sku", "barcode", "price", "stock", "warehouse", "image", "description")) {
  $matches = @($allMappings | Where-Object { $_.category -eq $category } | Select-Object -First 15)
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
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Upload this ZIP:" -ForegroundColor Yellow
Write-Host $zipPath -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to close..."
[void](Read-Host)
