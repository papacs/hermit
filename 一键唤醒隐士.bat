@echo off
setlocal

set "HERMIT_ROOT=%~dp0"
set "HERMIT_INSTALL=%HERMIT_ROOT%scripts\install.ps1"

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Requesting administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%HERMIT_ROOT%' -Verb RunAs"
    exit /b
)

if not exist "%HERMIT_INSTALL%" (
    echo Missing installer script: %HERMIT_INSTALL%
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERMIT_INSTALL%"
set "HERMIT_EXIT=%ERRORLEVEL%"

echo.
echo Hermit installer finished with exit code %HERMIT_EXIT%.
pause
exit /b %HERMIT_EXIT%

