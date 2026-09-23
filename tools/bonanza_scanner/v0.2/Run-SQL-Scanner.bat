@echo off
setlocal
title Altayebat Bonanza SQL Scanner v0.2

echo.
echo ================================================================
echo   ALTAYEBAT BONANZA SQL SCANNER v0.2
echo   READ-ONLY SQL METADATA MODE
echo ================================================================
echo.
echo This scanner uses Windows Integrated Authentication.
echo It executes SELECT statements only against SQL metadata.
echo No stock, price, invoice or product data is modified.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Altayebat-Bonanza-SQL-Scanner.ps1"

echo.
if errorlevel 1 (
  echo The scanner could not complete.
  echo Take a screenshot of this window and send it to the Altayebat project chat.
  pause
)

endlocal
