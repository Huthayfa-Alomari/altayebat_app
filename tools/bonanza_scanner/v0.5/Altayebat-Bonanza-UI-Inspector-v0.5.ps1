param(
  [string]$OutputRoot = "",
  [int]$MaxElements = 5000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Version = "0.5.0"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-ControlTypeName {
  param($Element)
  try {
    return [string]$Element.Current.ControlType.ProgrammaticName
  } catch {
    return ""
  }
}

function Get-ElementValue {
  param($Element)

  try {
    $pattern = $null
    if ($Element.TryGetCurrentPattern(
      [System.Windows.Automation.ValuePattern]::Pattern,
      [ref]$pattern
    )) {
      return [string]$pattern.Current.Value
    }
  } catch {}

  return ""
}

function Get-ElementSummary {
  param(
    $Element,
    [int]$Depth,
    [int]$Index
  )

  $name = ""
  $automationId = ""
  $className = ""
  $frameworkId = ""
  $isEnabled = $false
  $isOffscreen = $false

  try { $name = [string]$Element.Current.Name } catch {}
  try { $automationId = [string]$Element.Current.AutomationId } catch {}
  try { $className = [string]$Element.Current.ClassName } catch {}
  try { $frameworkId = [string]$Element.Current.FrameworkId } catch {}
  try { $isEnabled = [bool]$Element.Current.IsEnabled } catch {}
  try { $isOffscreen = [bool]$Element.Current.IsOffscreen } catch {}

  return [ordered]@{
    index = $Index
    depth = $Depth
    name = $name
    automation_id = $automationId
    control_type = Get-ControlTypeName $Element
    class_name = $className
    framework_id = $frameworkId
    enabled = $isEnabled
    offscreen = $isOffscreen
    value = Get-ElementValue $Element
  }
}

function Get-UiTree {
  param(
    $RootElement,
    [int]$Limit
  )

  $items = New-Object System.Collections.Generic.List[object]
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue([pscustomobject]@{
    Element = $RootElement
    Depth = 0
  })

  $index = 0

  while ($queue.Count -gt 0 -and $items.Count -lt $Limit) {
    $node = $queue.Dequeue()
    $element = $node.Element
    $depth = [int]$node.Depth

    $items.Add((Get-ElementSummary -Element $element -Depth $depth -Index $index))
    $index++

    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($element)

    while ($null -ne $child -and $items.Count + $queue.Count -lt $Limit) {
      $queue.Enqueue([pscustomobject]@{
        Element = $child
        Depth = $depth + 1
      })
      $child = $walker.GetNextSibling($child)
    }
  }

  return @($items)
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA UI INSPECTOR v$Version" -ForegroundColor Green
Write-Host "Windows UI Automation discovery only." -ForegroundColor Yellow
Write-Host "No SQL access. No mouse clicks. No keyboard input. No application changes." -ForegroundColor DarkGray
Write-Host ""

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_UI_Scan_" + $stamp)
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host "[1/4] Looking for Bonanza/Gravity windows..." -ForegroundColor Cyan

$processes = @(
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.MainWindowHandle -ne 0 -and (
        $_.ProcessName -match '(?i)(bonanza|gravity|inventory|stock|warehouse|pos|erp)' -or
        $_.MainWindowTitle -match '(?i)(bonanza|gravity|inventory|stock|warehouse|pos|erp)'
      )
    }
)

if ($processes.Count -eq 0) {
  Write-Host ""
  Write-Host "No matching Bonanza/Gravity window was found." -ForegroundColor Yellow
  Write-Host "Open Bonanza, navigate to the PRODUCTS / STOCK screen, then run this tool again."
  Write-Host ""
  [void](Read-Host "Press Enter to close")
  exit 2
}

$windows = @()
$allElements = @()

Write-Host ("Found windows: " + $processes.Count)

Write-Host "[2/4] Reading UI Automation tree..." -ForegroundColor Cyan

foreach ($p in $processes) {
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    if ($null -eq $root) { continue }

    $elements = @(Get-UiTree -RootElement $root -Limit $MaxElements)

    $windows += [ordered]@{
      process_name = $p.ProcessName
      process_id = $p.Id
      window_title = $p.MainWindowTitle
      element_count = $elements.Count
    }

    foreach ($element in $elements) {
      $allElements += [ordered]@{
        process_name = $p.ProcessName
        process_id = $p.Id
        window_title = $p.MainWindowTitle
        index = $element.index
        depth = $element.depth
        name = $element.name
        automation_id = $element.automation_id
        control_type = $element.control_type
        class_name = $element.class_name
        framework_id = $element.framework_id
        enabled = $element.enabled
        offscreen = $element.offscreen
        value = $element.value
      }
    }
  } catch {}
}

Write-Host "[3/4] Classifying useful controls..." -ForegroundColor Cyan

$interesting = @(
  $allElements |
    Where-Object {
      $_.control_type -match '(?i)(DataGrid|DataItem|Table|List|ListItem|Edit|Button|ComboBox|Tab|Text)' -or
      $_.name -match '(?i)(product|item|stock|quantity|qty|price|barcode|warehouse|صنف|مخزون|كمية|سعر|باركود|مستودع)'
    }
)

$report = [ordered]@{
  safety = [ordered]@{
    mode = "windows_ui_automation_read_only"
    sql_access = $false
    mouse_input_sent = $false
    keyboard_input_sent = $false
    application_data_modified = $false
    screenshots_captured = $false
  }
  scanner_version = $Version
  scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  windows = $windows
  total_elements = $allElements.Count
  interesting_controls = $interesting
  ui_tree = $allElements
}

$jsonPath = Join-Path $OutputRoot "bonanza_ui_tree.json"
$summaryPath = Join-Path $OutputRoot "bonanza_ui_summary.txt"

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$typeGroups = @(
  $allElements |
    Group-Object control_type |
    Sort-Object Count -Descending |
    Select-Object -First 20
)

$summary = @(
  "ALTAYEBAT BONANZA UI INSPECTOR v$Version",
  "",
  "SAFETY",
  "- Windows UI Automation read-only discovery",
  "- No SQL/database access",
  "- No mouse clicks",
  "- No keyboard input",
  "- No screenshots",
  "- No application changes",
  "",
  "WINDOWS"
)

foreach ($w in $windows) {
  $summary += "- $($w.process_name) [$($w.process_id)] :: $($w.window_title) :: elements=$($w.element_count)"
}

$summary += ""
$summary += "TOP CONTROL TYPES"

foreach ($g in $typeGroups) {
  $summary += "- $($g.Name): $($g.Count)"
}

$summary += ""
$summary += "INTERESTING CONTROLS: $($interesting.Count)"
foreach ($i in ($interesting | Select-Object -First 100)) {
  $summary += "- [$($i.control_type)] name='$($i.name)' automation_id='$($i.automation_id)' class='$($i.class_name)'"
}

$summary += ""
$summary += "Upload the generated ZIP to the Altayebat project chat."
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "[4/4] Creating ZIP..." -ForegroundColor Cyan
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
[void](Read-Host "Press Enter to close")
