@echo off
title CookieDrop
cd /d "%~dp0"

if not exist "%~dp0config.json" (
  echo.
  echo   config.json is missing next to this file.
  echo   Use the built zip or exe, not the source folder.
  echo.
  pause
  exit /b 1
)

powershell -NoP -Exec Bypass -c "Get-ChildItem '%~dp0' -File | Unblock-File" >nul 2>&1

echo.
echo   CookieDrop is starting in the background.
echo   This window closes by itself. Browsers may blink shut and reopen.
echo.
start "" /min wscript.exe "%~dp0RUN.vbs"
timeout /t 8 >nul
exit