# Altayebat Bonanza SQL Scanner v0.2

This is the second-stage scanner for the Altayebat ↔ Bonanza integration.

The first scan confirmed a local Microsoft SQL Server default instance is running on the Bonanza server. v0.2 connects with **Windows Integrated Authentication** and inspects SQL Server **metadata only**.

## Safety

- ApplicationIntent=ReadOnly
- SELECT statements only
- No INSERT / UPDATE / DELETE / EXEC
- No business rows exported
- No changes to Bonanza, SQL Server, registry, services, files or inventory

## What it collects

- SQL Server version/edition
- Accessible user database names
- Table names
- Column names and data types
- Candidate Product / SKU / Barcode / Price / Stock / Warehouse / Image fields
- A ranking of which database is most likely to be Bonanza

## Run

Double-click **Run-SQL-Scanner.bat** on the same Windows computer named SERVER where Bonanza/SQL Server runs.

When complete, upload:

**Altayebat_Bonanza_SQL_Scan_YYYYMMDD_HHMMSS.zip**

to the Altayebat project chat.

If Windows Integrated Authentication is denied, the tool exits without making any change. Send a screenshot of the error; do not send any database password.
