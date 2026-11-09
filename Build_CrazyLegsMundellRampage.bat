@echo off
setlocal
title Build Crazy Legs Mundell Rampage
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
    set "MUNDELL_PY=python"
) else (
    set "MUNDELL_PY=py -3.12"
)
%MUNDELL_PY% -m venv .venv
if errorlevel 1 goto failed
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto failed
call build_windows.bat
if errorlevel 1 goto failed
echo.
echo Build finished. See the Executable path above.
pause
exit /b 0
:failed
echo.
echo Build failed. See the error above. Windows Python 3.12 x64 is recommended.
pause
exit /b 1

