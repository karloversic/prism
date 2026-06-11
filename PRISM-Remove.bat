@echo off

REM Check for admin privileges
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs -Wait" >nul 2>&1
    exit /b %errorlevel%
)

if exist "C:\PRISM\PRISM-Stop.ps1" (
    start "" powershell -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "C:\PRISM\PRISM-Stop.ps1"
) else if exist "%~dp0PRISM-Stop.ps1" (
    start "" powershell -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "%~dp0PRISM-Stop.ps1"
) else (
    echo [ERROR] PRISM-Stop.ps1 not found
    pause
)
