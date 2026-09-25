@echo off
setlocal
title Altayebat Bonanza Window Selector v0.6

echo.
echo ================================================================
echo   ALTAYEBAT BONANZA WINDOW SELECTOR + UI INSPECTOR v0.6
echo ================================================================
echo.
echo Keep Bonanza open on the PRODUCTS / STOCK screen.
echo The tool will list all visible windows.
echo Choose the number that belongs to Bonanza.
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Altayebat-Bonanza-UI-Inspector-v0.6.ps1"

if errorlevel 1 (
  echo.
  echo The scan did not complete. Take a screenshot of this window.
  pause
)

endlocal
