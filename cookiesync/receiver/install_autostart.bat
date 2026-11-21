@echo off
setlocal
cd /d "%~dp0.."
set PY=
where py >nul 2>&1 && set PY=py -3
if not defined PY where python >nul 2>&1 && set PY=python
if not defined PY ( echo Python 3 not found. & pause & exit /b 1 )

for /f "tokens=2 delims=:," %%A in ('findstr /i "\"port\"" config.json 2^>nul') do set PORT=%%A
for /f "tokens=2 delims=:," %%A in ('findstr /i "\"discovery_port\"" config.json 2^>nul') do set DPORT=%%A
set PORT=%PORT: =%
set DPORT=%DPORT: =%
if "%PORT%"=="" set PORT=8000
if "%DPORT%"=="" set DPORT=50505

%PY% -m pip install -q --disable-pip-version-check -r requirements.txt

netsh advfirewall firewall delete rule name="CookieSync TCP" >nul 2>&1
netsh advfirewall firewall add rule name="CookieSync TCP" dir=in action=allow protocol=TCP localport=%PORT% >nul
netsh advfirewall firewall delete rule name="CookieSync UDP" >nul 2>&1
netsh advfirewall firewall add rule name="CookieSync UDP" dir=in action=allow protocol=UDP localport=%DPORT% >nul

schtasks /delete /tn CookieSyncReceiver /f >nul 2>&1
schtasks /create /tn CookieSyncReceiver /tr "wscript.exe \"%~dp0run_hidden.vbs\"" /sc onlogon /rl limited /f

echo.
echo   Firewall rules added for TCP %PORT% and UDP %DPORT%.
echo   Logon task CookieSyncReceiver created.
echo.
pause