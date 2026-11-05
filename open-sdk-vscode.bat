@echo off
setlocal
cd /d "%~dp0"

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" (
    echo ERROR: Windows PowerShell is unavailable.
    pause
    exit /b 2
)

set "WORKSPACE_HELPER=%~dp0sdk\open-sdk-vscode.ps1"
if not exist "%WORKSPACE_HELPER%" set "WORKSPACE_HELPER=%~dp0open-sdk-vscode.ps1"
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%WORKSPACE_HELPER%"
set "OPEN_EXIT_CODE=%ERRORLEVEL%"
if not "%OPEN_EXIT_CODE%"=="0" (
    echo.
    echo Failed to open the PyMotion Lite SDK workspace.
    pause
)
exit /b %OPEN_EXIT_CODE%
