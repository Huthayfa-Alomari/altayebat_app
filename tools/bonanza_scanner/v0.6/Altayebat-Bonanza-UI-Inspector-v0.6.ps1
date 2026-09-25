param(
  [string]$OutputRoot = "",
  [int]$MaxElements = 12000
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Version = "0.6.0"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Get-ControlTypeName {
  param($Element)
  try { return [string]$Element.Current.ControlType.ProgrammaticName } catch { return "" }
}

function Get-PatternNames {
  param($Element)

  $names = New-Object System.Collections.Generic.List[string]
  $patterns = @(
    @{ Name = "Value"; Pattern = [System.Windows.Automation.ValuePattern]::Pattern },
    @{ Name = "Text"; Pattern = [System.Windows.Automation.TextPattern]::Pattern },
    @{ Name = "Grid"; Pattern = [System.Windows.Automation.GridPattern]::Pattern },
    @{ Name = "GridItem"; Pattern = [System.Windows.Automation.GridItemPattern]::Pattern },
    @{ Name = "Table"; Pattern = [System.Windows.Automation.TablePattern]::Pattern },
    @{ Name = "TableItem"; Pattern = [System.Windows.Automation.TableItemPattern]::Pattern },
    @{ Name = "Selection"; Pattern = [System.Windows.Automation.SelectionPattern]::Pattern },
    @{ Name = "SelectionItem"; Pattern = [System.Windows.Automation.SelectionItemPattern]::Pattern },
    @{ Name = "Scroll"; Pattern = [System.Windows.Automation.ScrollPattern]::Pattern },
    @{ Name = "Invoke"; Pattern = [System.Windows.Automation.InvokePattern]::Pattern },
    @{ Name = "ExpandCollapse"; Pattern = [System.Windows.Automation.ExpandCollapsePattern]::Pattern },
    @{ Name = "LegacyIAccessible"; Pattern = [System.Windows.Automation.LegacyIAccessiblePattern]::Pattern }
  )

  foreach ($p in $patterns) {
    try {
      $obj = $null
      if ($Element.TryGetCurrentPattern($p.Pattern, [ref]$obj)) {
        $names.Add($p.Name)
      }
    } catch {}
  }

  return @($names)
}

function Get-ElementValue {
  param($Element)

  try {
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
      return [string]$pattern.Current.Value
    }
  } catch {}

  try {
    $legacy = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern,[ref]$legacy)) {
      return [string]$legacy.Current.Value
    }
  } catch {}

  return ""
}

function Get-LegacyInfo {
  param($Element)

  $name = ""
  $value = ""
  $role = ""
  $state = ""

  try {
    $legacy = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern,[ref]$legacy)) {
      $name = [string]$legacy.Current.Name
      $value = [string]$legacy.Current.Value
      $role = [string]$legacy.Current.Role
      $state = [string]$legacy.Current.State
    }
  } catch {}

  return [ordered]@{
    name = $name
    value = $value
    role = $role
    state = $state
  }
}

function Get-ElementSummary {
  param($Element,[int]$Depth,[int]$Index)

  $rect = $null
  try { $rect = $Element.Current.BoundingRectangle } catch {}

  $name = ""
  $automationId = ""
  $className = ""
  $frameworkId = ""
  $nativeWindowHandle = 0
  $enabled = $false
  $offscreen = $false
  $focusable = $false

  try { $name = [string]$Element.Current.Name } catch {}
  try { $automationId = [string]$Element.Current.AutomationId } catch {}
  try { $className = [string]$Element.Current.ClassName } catch {}
  try { $frameworkId = [string]$Element.Current.FrameworkId } catch {}
  try { $nativeWindowHandle = [int]$Element.Current.NativeWindowHandle } catch {}
  try { $enabled = [bool]$Element.Current.IsEnabled } catch {}
  try { $offscreen = [bool]$Element.Current.IsOffscreen } catch {}
  try { $focusable = [bool]$Element.Current.IsKeyboardFocusable } catch {}

  $legacy = Get-LegacyInfo $Element

  $bounds = $null
  if ($null -ne $rect) {
    $bounds = [ordered]@{
      x = [double]$rect.X
      y = [double]$rect.Y
      width = [double]$rect.Width
      height = [double]$rect.Height
    }
  }

  return [ordered]@{
    index = $Index
    depth = $Depth
    name = $name
    automation_id = $automationId
    control_type = Get-ControlTypeName $Element
    class_name = $className
    framework_id = $frameworkId
    native_window_handle = $nativeWindowHandle
    enabled = $enabled
    offscreen = $offscreen
    focusable = $focusable
    value = Get-ElementValue $Element
    supported_patterns = @(Get-PatternNames $Element)
    legacy = $legacy
    bounds = $bounds
  }
}

function Get-UiTree {
  param($Root,[int]$Limit)

  $items = New-Object System.Collections.Generic.List[object]
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue([pscustomobject]@{ Element = $Root; Depth = 0 })

  $index = 0
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker

  while ($queue.Count -gt 0 -and $items.Count -lt $Limit) {
    $node = $queue.Dequeue()
    $element = $node.Element
    $depth = [int]$node.Depth

    $items.Add((Get-ElementSummary -Element $element -Depth $depth -Index $index))
    $index++

    $child = $walker.GetFirstChild($element)
    while ($null -ne $child -and ($items.Count + $queue.Count) -lt $Limit) {
      $queue.Enqueue([pscustomobject]@{ Element = $child; Depth = $depth + 1 })
      $child = $walker.GetNextSibling($child)
    }
  }

  return @($items)
}

Write-Host ""
Write-Host "ALTAYEBAT BONANZA WINDOW SELECTOR + UI INSPECTOR v$Version" -ForegroundColor Green
Write-Host "Read-only Windows UI Automation." -ForegroundColor Yellow
Write-Host "No SQL access. No clicks. No keyboard input is sent to Bonanza." -ForegroundColor DarkGray
Write-Host ""

$visible = @(
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle) } |
    Sort-Object ProcessName, MainWindowTitle
)

if ($visible.Count -eq 0) {
  Write-Host "No visible application windows were found." -ForegroundColor Red
  [void](Read-Host "Press Enter to close")
  exit 2
}

Write-Host "Open Bonanza on the PRODUCTS / STOCK screen." -ForegroundColor Cyan
Write-Host "Then choose the Bonanza window from this list:" -ForegroundColor Cyan
Write-Host ""

for ($i = 0; $i -lt $visible.Count; $i++) {
  $p = $visible[$i]
  Write-Host ("[{0}] {1}  |  {2}" -f ($i + 1), $p.ProcessName, $p.MainWindowTitle)
}

Write-Host ""
$selection = Read-Host "Enter window number"

[int]$selectedIndex = 0
if (-not [int]::TryParse($selection, [ref]$selectedIndex)) {
  Write-Host "Invalid number." -ForegroundColor Red
  exit 3
}
$selectedIndex--

if ($selectedIndex -lt 0 -or $selectedIndex -ge $visible.Count) {
  Write-Host "Selection is outside the available range." -ForegroundColor Red
  exit 3
}

$process = $visible[$selectedIndex]

Write-Host ""
Write-Host ("Selected: " + $process.ProcessName + " | " + $process.MainWindowTitle) -ForegroundColor Green

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:TEMP }
  $OutputRoot = Join-Path $desktop ("Altayebat_Bonanza_UI_Scan_v06_" + $stamp)
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

Write-Host "[1/3] Reading selected window through UI Automation..." -ForegroundColor Cyan

try {
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
} catch {
  $root = $null
}

if ($null -eq $root) {
  Write-Host "Windows UI Automation could not attach to the selected window." -ForegroundColor Red
  [void](Read-Host "Press Enter to close")
  exit 4
}

$elements = @(Get-UiTree -Root $root -Limit $MaxElements)

Write-Host ("UI elements discovered: " + $elements.Count)

Write-Host "[2/3] Classifying product/stock-related controls..." -ForegroundColor Cyan

$interesting = @(
  $elements |
    Where-Object {
      $_.control_type -match '(?i)(DataGrid|DataItem|Table|List|ListItem|Edit|Button|ComboBox|Tab|Text|Pane|Custom|Header|HeaderItem)' -or
      $_.name -match '(?i)(product|item|stock|quantity|qty|price|barcode|warehouse|code|name|صنف|مخزون|كمية|سعر|باركود|مستودع|كود|اسم)' -or
      $_.legacy.name -match '(?i)(product|item|stock|quantity|qty|price|barcode|warehouse|code|name|صنف|مخزون|كمية|سعر|باركود|مستودع|كود|اسم)'
    }
)

$patternGroups = @()
foreach ($e in $elements) {
  foreach ($pattern in $e.supported_patterns) {
    $patternGroups += $pattern
  }
}
$patternSummary = @(
  $patternGroups |
    Group-Object |
    Sort-Object Count -Descending |
    ForEach-Object {
      [ordered]@{ pattern = $_.Name; count = $_.Count }
    }
)

$typeSummary = @(
  $elements |
    Group-Object control_type |
    Sort-Object Count -Descending |
    ForEach-Object {
      [ordered]@{ control_type = $_.Name; count = $_.Count }
    }
)

$report = [ordered]@{
  safety = [ordered]@{
    mode = "selected_window_ui_automation_read_only"
    sql_access = $false
    mouse_input_sent = $false
    keyboard_input_sent_to_application = $false
    screenshots_captured = $false
    application_data_modified = $false
  }
  scanner_version = $Version
  scanned_at_utc = (Get-Date).ToUniversalTime().ToString("o")
  selected_window = [ordered]@{
    process_name = $process.ProcessName
    process_id = $process.Id
    window_title = $process.MainWindowTitle
  }
  total_elements = $elements.Count
  interesting_control_count = $interesting.Count
  control_type_summary = $typeSummary
  pattern_summary = $patternSummary
  interesting_controls = $interesting
  ui_tree = $elements
}

$jsonPath = Join-Path $OutputRoot "bonanza_ui_tree_v06.json"
$summaryPath = Join-Path $OutputRoot "bonanza_ui_summary_v06.txt"

$report | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding UTF8

$summary = @(
  "ALTAYEBAT BONANZA UI INSPECTOR v$Version",
  "",
  "SELECTED WINDOW",
  "- Process: $($process.ProcessName)",
  "- PID: $($process.Id)",
  "- Title: $($process.MainWindowTitle)",
  "",
  "RESULT",
  "- UI elements: $($elements.Count)",
  "- Interesting controls: $($interesting.Count)",
  "",
  "TOP CONTROL TYPES"
)

foreach ($g in ($typeSummary | Select-Object -First 30)) {
  $summary += "- $($g.control_type): $($g.count)"
}

$summary += ""
$summary += "SUPPORTED UI PATTERNS"
foreach ($g in $patternSummary) {
  $summary += "- $($g.pattern): $($g.count)"
}

$summary += ""
$summary += "INTERESTING CONTROLS"
foreach ($e in ($interesting | Select-Object -First 200)) {
  $patterns = ($e.supported_patterns -join ",")
  $summary += "- [$($e.control_type)] name='$($e.name)' id='$($e.automation_id)' class='$($e.class_name)' patterns=[$patterns]"
}

$summary += ""
$summary += "Upload the generated ZIP to the Altayebat project chat."
$summary | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "[3/3] Creating ZIP..." -ForegroundColor Cyan
$zipPath = $OutputRoot + ".zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $OutputRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Upload this ZIP:" -ForegroundColor Yellow
Write-Host $zipPath -ForegroundColor Yellow
Write-Host ""
[void](Read-Host "Press Enter to close")
