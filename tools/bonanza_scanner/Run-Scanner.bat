@echo off
setlocal
title Altayebat Bonanza Scanner

echo.
echo ================================================================
echo   ALTAYEBAT BONANZA SCANNER
echo   Read-only discovery - no database changes
echo ================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Altayebat-Bonanza-Scanner.ps1"

echo.
if errorlevel 1 (
  echo Scanner returned an error.
  echo Take a screenshot of this window and send it to the Altayebat project chat.
  pause
)

endlocal
