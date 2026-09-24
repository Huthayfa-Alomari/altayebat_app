# Altayebat Bonanza UI Inspector v0.5

Use this when Bonanza has no API, no export/report function, and SQL access is unavailable.

## Goal

Determine whether Bonanza exposes its product/stock screen through Windows UI Automation so the production Altayebat Bridge can automate the existing desktop application without database access.

## Before running

1. Open Bonanza.
2. Navigate to the screen that shows products, stock, prices or barcodes.
3. Leave that screen visible.
4. Run **Run-UI-Inspector-v0.5.bat**.

## Safety

- No SQL/database access.
- No mouse clicks.
- No keyboard input.
- No screenshots.
- No registry/service changes.
- No application changes.

The tool only reads the Windows accessibility/UI Automation tree of the visible Bonanza window.

## Output

A Desktop ZIP named:

**Altayebat_Bonanza_UI_Scan_YYYYMMDD_HHMMSS.zip**

Upload that ZIP to the Altayebat project chat.

From the report we can determine whether the production bridge can reliably read Bonanza DataGrid/List/Edit controls and which AutomationIds/control classes should be targeted.
