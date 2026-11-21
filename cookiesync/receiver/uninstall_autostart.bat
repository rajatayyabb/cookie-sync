@echo off
schtasks /delete /tn CookieSyncReceiver /f >nul 2>&1
netsh advfirewall firewall delete rule name="CookieSync TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="CookieSync UDP" >nul 2>&1
echo Removed task and firewall rules.
pause