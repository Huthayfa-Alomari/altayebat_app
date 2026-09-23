# Altayebat Bonanza Scanner v0.1

Windows read-only discovery utility for the Altayebat ↔ Bonanza integration.

## What it detects

- Bonanza / Gravity installation folders and executable metadata.
- Running Bonanza/Gravity processes.
- SQL Server / SQL Express / MySQL / PostgreSQL / Firebird / InterBase services.
- SQL Server instances.
- Common database files: MDF/LDF, Access, SQLite, Firebird and related formats.
- Sanitized configuration clues such as server/database/path/provider.
- Product-image folders.
- Backup-file candidates.
- Common local database listener ports.

## Safety

The scanner is intentionally read-only:

- No database connection is opened.
- No SQL query is executed.
- No registry key is changed.
- No Windows service is changed.
- No Bonanza file is changed.
- Common Password/Pwd/User ID/UID/Username values are redacted from configuration excerpts.

The only files it creates are its own report folder and ZIP on the Windows Desktop.

## Run it at the supermarket

1. Copy this folder to the Windows PC that runs Bonanza.
2. Bonanza can stay open.
3. Double-click **Run-Scanner.bat**.
4. Normal user permissions are enough for the first run.
5. When finished, the Desktop will contain:
   **Altayebat_Bonanza_Scan_YYYYMMDD_HHMMSS.zip**
6. Upload that ZIP to the Altayebat project chat.

## Output

- **bonanza_scan_report.json** — structured report.
- **bonanza_scan_summary.txt** — short readable summary.

## After the scan

The report tells us which adapter to build:

- SQL Server adapter
- Firebird adapter
- Access adapter
- SQLite adapter
- Export/CSV adapter
- Desktop/RPA adapter as a last resort

The production bridge will keep Bonanza as the source of truth for inventory while Supabase powers the customer app.
