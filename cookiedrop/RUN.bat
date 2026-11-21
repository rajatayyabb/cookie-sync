@echo off
title CookieDrop - debug
cd /d "%~dp0"
powershell -NoP -Exec Bypass -c "Get-ChildItem '%~dp0' -File | Unblock-File" >nul 2>&1
echo.
echo   Running visible. Full output below.
echo.
powershell -NoP -Exec Bypass -File "%~dp0CookieDrop.ps1" -Visible %*
echo.
echo   Logs: %LOCALAPPDATA%\CookieDrop\logs
echo.
pause