@echo off
setlocal
set LINK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\CookieSync.lnk
if exist "%LINK%" del /q "%LINK%" && echo Removed startup shortcut.
netsh advfirewall firewall delete rule name="CookieSync TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="CookieSync UDP" >nul 2>&1
netsh advfirewall firewall delete rule name="CookieSync TCP out" >nul 2>&1
echo Removed firewall rules.
pause