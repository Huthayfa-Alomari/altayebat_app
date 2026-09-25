# Altayebat Bonanza SQL Scanner v0.3

v0.2 confirmed that Windows Integrated Authentication fails because the Windows account used on SERVER is disabled.

v0.3 uses a **dedicated SQL Login** instead.

## Recommended setup

Ask the Bonanza/SQL administrator to open SQL Server Management Studio and run:

**CREATE-READONLY-SCANNER-LOGIN.sql**

They must replace the placeholder password locally.

Do **not** send the SQL password to ChatGPT.

## What v0.3 reads

- SQL Server identity/version
- accessible user database names
- table names
- column names and types
- candidate Product / SKU / Barcode / Price / Stock / Warehouse / Image fields

It does **not** export product rows, prices, stock values, customer records, invoices, or accounting data.

## Safety

- ApplicationIntent=ReadOnly
- hard safety check rejects non-SELECT queries
- no INSERT / UPDATE / DELETE / EXEC
- password is not written to disk
- password is not added to report files
- no source data is modified

## Run

1. Obtain the dedicated read-only SQL username/password from the authorized SQL administrator.
2. Double-click **Run-SQL-Scanner-v0.3.bat**
3. Enter the username and password locally.
4. Upload the generated Desktop ZIP:
   **Altayebat_Bonanza_SQL_Scan_v03_YYYYMMDD_HHMMSS.zip**
