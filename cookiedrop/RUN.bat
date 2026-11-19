@echo off
cd /d "%~dp0"
if not exist "%~dp0config.json" (
  echo.
  echo   config.json is missing.
  echo   Copy config.example.json to config.json and fill in at least one channel.
  echo.
  pause
  exit /b 1
)
powershell -NoP -NonI -Exec Bypass -WindowStyle Hidden -File "%~dp0cookies.ps1"
if errorlevel 1 (
  echo.
  echo   CookieDrop hit an error. A local copy may still be in %LOCALAPPDATA%\CookieDrop
  echo   Rerun without -WindowStyle Hidden to see the output:
  echo     powershell -NoP -Exec Bypass -File "%~dp0cookies.ps1"
  echo.
  pause
)
exit