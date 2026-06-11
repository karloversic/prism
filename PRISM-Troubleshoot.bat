@echo off
setlocal enabledelayedexpansion

openfiles >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs -Wait" >nul 2>&1
    exit /b %errorlevel%
)

chcp 65001 >nul 2>&1
cls
echo.
echo ================================================================================
echo  PRISM v1.0.0 - Troubleshoot Menu
echo  Partition Recycling and Intelligent Storage Management
echo ================================================================================
echo.
:menu
echo.
echo Select option:
echo.
echo [1] Check PRISM Installation Status
echo [2] Check PRISM-Monitor Task Status
echo [3] Restart PRISM-Monitor Task
echo [4] View PRISM Logs
echo [5] View Format Operation Logs
echo [6] View Backup Folders
echo [7] Create/Reset S: Drive
echo [8] Complete Reset Installation
echo [9] Full Diagnostic (All Checks)
echo [0] Exit
echo.
set /p choice="Enter your choice (0-9): "
cls
if "%choice%"=="1" goto check_status
if "%choice%"=="2" goto check_task
if "%choice%"=="3" goto restart_task
if "%choice%"=="4" goto view_logs
if "%choice%"=="5" goto view_format_logs
if "%choice%"=="6" goto view_backups
if "%choice%"=="7" goto create_drive
if "%choice%"=="8" goto reset_install
if "%choice%"=="9" goto full_diagnostic
if "%choice%"=="0" exit /b 0
echo Invalid choice
goto menu

:check_status
echo [INFO] Checking PRISM Installation...
if exist "C:\PRISM" (
    echo [OK] C:\PRISM exists
    echo [OK] Installation found at: C:\PRISM
    dir /b "C:\PRISM" | findstr /v "logs backup" >nul && echo [OK] Scripts present
) else (
    echo [ERROR] C:\PRISM not found - not installed
)
echo.
pause
goto menu

:check_task
echo [INFO] Checking PRISM-Monitor Task...
schtasks /query /tn PRISM-Monitor >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Task found
    schtasks /query /tn PRISM-Monitor /fo list
) else (
    echo [ERROR] Task not found - run PRISM-Deploy.bat to create
)
echo.
pause
goto menu

:restart_task
echo [INFO] Restarting PRISM-Monitor Task...
schtasks /run /tn PRISM-Monitor >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Task restarted
) else (
    echo [ERROR] Could not restart task
)
echo.
pause
goto menu

:view_logs
echo [INFO] Opening PRISM logs folder...
if exist "C:\PRISM\logs" (
    start "" "C:\PRISM\logs"
    echo [OK] Logs folder opened
) else (
    echo [ERROR] Logs folder not found
)
echo.
pause
goto menu

:view_format_logs
echo [INFO] Opening Format Operation logs...
if exist "C:\PRISM\logs\format-logs" (
    start "" "C:\PRISM\logs\format-logs"
    echo [OK] Format logs folder opened
) else (
    echo [ERROR] Format logs folder not found
)
echo.
pause
goto menu

:view_backups
echo [INFO] Opening Backups folder...
if exist "C:\PRISM\backup" (
    start "" "C:\PRISM\backup"
    echo [OK] Backup folder opened
) else (
    echo [ERROR] Backup folder not found
)
echo.
pause
goto menu

:create_drive
echo [INFO] Creating/Checking S: Drive...
echo.
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0PRISM-CreateSDrive.ps1"
if %errorlevel% equ 0 (
    echo.
    echo [OK] S: Drive ready
    if not exist "S:\target.marker" (
        echo [INFO] Creating target.marker...
        echo PRISM_TARGET > S:\target.marker
        echo [OK] target.marker created
    ) else (
        echo [OK] target.marker already exists
    )
) else (
    echo [ERROR] S: Drive creation failed
)
echo.
pause
goto menu

:reset_install
echo [WARNING] This will reset PRISM installation
set /p confirm="Continue? (Y/N): "
if /i not "%confirm%"=="Y" goto menu
echo [INFO] Removing PRISM...
schtasks /delete /tn PRISM-Monitor /f >nul 2>&1
schtasks /delete /tn PRISM-Config  /f >nul 2>&1
echo [OK] Tasks deleted

echo [INFO] Stopping tray process...
wmic process where "CommandLine like '%%PRISM-Tray%%'" delete >nul 2>&1
echo [OK] Tray process stopped

echo [INFO] Cleaning registry...
reg delete "HKLM\SOFTWARE\PRISM" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "PRISM-Tray" /f >nul 2>&1
echo [OK] Registry cleaned

echo [INFO] Detaching VHD (if mounted)...
if exist "C:\PRISM\PRISM.vhd" (
    echo select vdisk file=C:\PRISM\PRISM.vhd> "%TEMP%\prism_detach.txt"
    echo detach vdisk noerr>> "%TEMP%\prism_detach.txt"
    echo exit>> "%TEMP%\prism_detach.txt"
    diskpart /s "%TEMP%\prism_detach.txt" >nul 2>&1
    del /f /q "%TEMP%\prism_detach.txt" >nul 2>&1
    timeout /t 3 /nobreak >nul 2>&1
    echo [OK] VHD detach attempted
)

if exist "C:\PRISM" (
    rmdir /s /q "C:\PRISM" >nul 2>&1
    if exist "C:\PRISM" (
        echo [WARNING] C:\PRISM could not be fully removed - some files may still be locked
    ) else (
        echo [OK] C:\PRISM removed
    )
)
echo [SUCCESS] Reset complete - run PRISM-Deploy.bat to reinstall
echo.
pause
goto menu

:full_diagnostic
echo [=== PRISM FULL DIAGNOSTIC ===]
echo.
echo [1/5] Checking C:\PRISM folder...
if exist "C:\PRISM" (
    echo [OK] C:\PRISM exists
) else (
    echo [ERROR] C:\PRISM missing
)
echo.
echo [2/5] Checking S: drive...
if exist "S:\" (
    echo [OK] S: drive exists
    for /f "tokens=3" %%A in ('dir S:\ ^| find "bytes free"') do (
        echo [INFO] S: drive info: %%A
    )
) else (
    echo [ERROR] S: drive not found
)
echo.
echo [3/5] Checking target.marker...
if exist "S:\target.marker" (
    echo [OK] S:\target.marker exists
    type S:\target.marker
) else (
    echo [ERROR] S:\target.marker not found
)
echo.
echo [4/5] Checking PRISM-Monitor task...
schtasks /query /tn PRISM-Monitor >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Task exists
) else (
    echo [ERROR] Task not found
)
echo.
echo [5/5] Checking Registry...
reg query "HKLM\SOFTWARE\PRISM" >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Registry entries exist
) else (
    echo [ERROR] Registry entries not found
)
echo.
echo [=== DIAGNOSTIC COMPLETE ===]
echo.
pause
goto menu
