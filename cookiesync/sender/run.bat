@echo off
setlocal
cd /d "%~dp0"
set PY=
where py >nul 2>&1 && set PY=py -3
if not defined PY where python >nul 2>&1 && set PY=python
if not defined PY ( echo Python 3 not found. & pause & exit /b 1 )
%PY% -m pip install -q --disable-pip-version-check -r "%~dp0..\requirements.txt"
%PY% "%~dp0sender.py" %*
if errorlevel 1 pause