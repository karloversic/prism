param(
    [string]$USBDrivePath = $PSScriptRoot,
    [string]$InstallationPath = "C:\PRISM",
    [string]$LogsPath = "C:\PRISM\logs",
    [int]$DriveSize = 50,
    [int]$CapacityThreshold = 95,
    [int]$PreserveFolders = 5,
    [int]$MonitoringInterval = 8
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "Configuring Task Scheduler and Registry..." -ForegroundColor Cyan
Write-Host ""

try {
    $TaskName = "PRISM-Monitor"
    $ScriptPath = Join-Path $InstallationPath "PRISM.ps1"

    Write-Host "[INFO] Creating Task Scheduler task..." -ForegroundColor Cyan

    $triggerStartup = New-ScheduledTaskTrigger -AtStartup
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $MonitoringInterval) -RepetitionDuration (New-TimeSpan -Days 9999)

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy RemoteSigned -File `"$ScriptPath`" -Action Monitor -LogsPath `"$LogsPath`""

    # -AllowStartIfOnBatteries / -DontStopIfGoingOnBatteries are REQUIRED: without them
    # New-ScheduledTaskSettingsSet defaults DisallowStartIfOnBatteries=$true and
    # StopIfGoingOnBatteries=$true, so on a laptop running on battery Task Scheduler
    # silently refuses to start PRISM-Monitor (and kills it if it goes on battery
    # mid-run) — the monitor never runs and the drive never gets recycled.
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false `
        -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest -LogonType ServiceAccount

    Register-ScheduledTask -TaskName $TaskName `
        -Action $action `
        -Trigger @($triggerStartup, $triggerRepeat) `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null

    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        throw "Task '$TaskName' was not found after registration"
    }

    Write-Host "[OK] Task created: $TaskName" -ForegroundColor Green

    Write-Host "[INFO] Creating PRISM-Config task..." -ForegroundColor Cyan

    $configScriptPath = Join-Path $InstallationPath "PRISM-Config.ps1"
    $configAction     = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File `"$configScriptPath`""
    # Battery flags here too: DisallowStartIfOnBatteries also blocks manual
    # Start-ScheduledTask, so without these the tray could not open the Config GUI
    # while the machine is on battery.
    $configSettings   = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
                            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $configPrincipal  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                            -RunLevel Highest -LogonType Interactive
    $configTask       = New-ScheduledTask -Action $configAction -Settings $configSettings -Principal $configPrincipal
    Register-ScheduledTask -TaskName "PRISM-Config" -InputObject $configTask -Force | Out-Null

    Write-Host "[OK] Task created: PRISM-Config (no UAC on launch)" -ForegroundColor Green

    Write-Host "[INFO] Setting up Registry..." -ForegroundColor Cyan

    $regPath = "HKLM:\SOFTWARE\PRISM"
    if(-not(Test-Path $regPath)) {
        New-Item -Path "HKLM:\SOFTWARE" -Name "PRISM" -Force | Out-Null
        Write-Host "[OK] Registry key created" -ForegroundColor Green
    }

    Set-ItemProperty -Path $regPath -Name "InstallPath" -Value $InstallationPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "LogsPath" -Value $LogsPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "Version" -Value "1.0.0" -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "TargetDrive" -Value "S:" -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "CapacityThreshold"  -Value $CapacityThreshold  -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "PreserveFolders"    -Value $PreserveFolders    -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "MonitoringInterval" -Value $MonitoringInterval -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "DriveSize"          -Value $DriveSize          -Force | Out-Null

    Write-Host "[OK] Registry configured" -ForegroundColor Green

    Write-Host "[SUCCESS] Configuration complete!" -ForegroundColor Green
    Write-Host ""
    exit 0
}
catch {
    $errMsg = "$_"
    Write-Host "[ERROR] Configuration failed: $errMsg" -ForegroundColor Red
    try { $errMsg | Out-File "$LogsPath\deploy-error.txt" -Force -Encoding UTF8 } catch {}
    exit 1
}
