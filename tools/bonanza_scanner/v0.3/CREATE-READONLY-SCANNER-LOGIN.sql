/*
ALTAYEBAT / BONANZA - READ-ONLY METADATA LOGIN
Run this ONLY by the SQL Server administrator in SQL Server Management Studio.

Purpose:
- allow the Altayebat scanner to identify the Bonanza database/schema
- no write permissions
- no business-data SELECT permission is granted here

IMPORTANT:
1) Replace CHANGE_ME_STRONG_PASSWORD with a strong temporary password.
2) Give the username/password directly to the person running the scanner.
3) Do not paste the password into ChatGPT.
4) After schema discovery, this login can be disabled/dropped or narrowed further.
*/

USE [master];
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'altayebat_scan_ro')
BEGIN
    CREATE LOGIN [altayebat_scan_ro]
    WITH PASSWORD = N'CHANGE_ME_STRONG_PASSWORD',
         CHECK_POLICY = ON,
         CHECK_EXPIRATION = OFF;
END
GO

GRANT VIEW ANY DATABASE TO [altayebat_scan_ro];
GRANT CONNECT ANY DATABASE TO [altayebat_scan_ro];
GRANT VIEW ANY DEFINITION TO [altayebat_scan_ro];
GO

/*
Optional cleanup after the scan:

USE [master];
GO
DROP LOGIN [altayebat_scan_ro];
GO
*/
