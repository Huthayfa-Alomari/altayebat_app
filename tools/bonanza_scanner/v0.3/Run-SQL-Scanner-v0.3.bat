@echo off
setlocal
title Altayebat Bonanza SQL Scanner v0.3

echo.
echo ================================================================
echo   ALTAYEBAT BONANZA SQL SCANNER v0.3
echo   READ-ONLY SQL LOGIN MODE
echo ================================================================
echo.
echo You will be asked for a dedicated READ-ONLY SQL username/password.
echo The password is not stored in the output or written to disk.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Altayebat-Bonanza-SQL-Scanner-v0.3.ps1"

if errorlevel 1 (
  echo.
  echo Scanner did not complete.
  echo Do NOT send any password. Send only a screenshot of the error.
  pause
)

endlocal
