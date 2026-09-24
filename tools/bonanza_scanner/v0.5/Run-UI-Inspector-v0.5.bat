@echo off
setlocal
title Altayebat Bonanza UI Inspector v0.5

echo.
echo ================================================================
echo   ALTAYEBAT BONANZA UI INSPECTOR v0.5
echo   WINDOWS UI AUTOMATION - READ ONLY
echo ================================================================
echo.
echo 1. Open Bonanza.
echo 2. Navigate to the PRODUCTS / STOCK screen.
echo 3. Leave that screen visible.
echo 4. Press any key here to start the scan.
echo.
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Altayebat-Bonanza-UI-Inspector-v0.5.ps1"

if errorlevel 1 (
  echo.
  echo If the scan could not find Bonanza, keep Bonanza open on the products screen and run again.
  pause
)

endlocal
