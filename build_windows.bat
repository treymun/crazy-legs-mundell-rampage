@echo off
setlocal EnableDelayedExpansion
title Build Crazy Legs Mundell Rampage
cd /d "%~dp0"
set "PY=.venv\Scripts\python.exe"
if not exist "%PY%" set "PY=python"
"%PY%" -m PyInstaller --noconfirm CrazyLegsMundellRampage.spec
if errorlevel 1 goto failed
for /f "delims=" %%v in ('"%PY%" -c "from game_version import VERSION; print(VERSION)"') do set "VERSION=%%v"
copy /y "dist\CrazyLegsMundellRampage.exe" "dist\CrazyLegsMundellRampage-!VERSION!.exe" >nul
echo Built dist\CrazyLegsMundellRampage.exe and dist\CrazyLegsMundellRampage-!VERSION!.exe
set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%ISCC%" (
    "%ISCC%" /DMyAppFullVersion=!VERSION! installer.iss
    if errorlevel 1 goto failed
    echo Built the installer in dist.
) else (
    echo Inno Setup 6 was not found; skipping the installer.
)
exit /b 0
:failed
echo.
echo Build failed. See the error above.
exit /b 1
