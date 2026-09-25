# Altayebat Bonanza UI Inspector v0.6

v0.5 found zero matching windows because the Bonanza executable/window does not advertise a predictable Bonanza/Gravity name.

v0.6 removes that assumption.

## Run

1. Open Bonanza.
2. Navigate to the Products / Stock / Price / Barcode screen.
3. Run **Run-UI-Inspector-v0.6.bat**.
4. The tool lists all visible application windows.
5. Choose the number corresponding to Bonanza.
6. It reads only that selected window through Windows UI Automation.
7. Upload the generated **Altayebat_Bonanza_UI_Scan_v06_*.zip**.

## Safety

- No SQL/database access.
- No mouse clicks.
- No keyboard input is sent to Bonanza.
- No screenshots.
- No application or Windows configuration changes.
- Only the selected application's UI Automation tree is written to the report.

v0.6 uses the UI Automation **RawView** tree and also records supported Grid/Table/Value/LegacyIAccessible patterns, which gives better coverage for older Win32/.NET desktop applications.
