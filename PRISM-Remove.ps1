param(
    [string]$DriveLetter = "S",
    [switch]$Wait
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host "PRISM - Complete Removal" -ForegroundColor Yellow
Write-Host "================================================================================" -ForegroundColor Yellow
Write-Host ""

$vhdPath = "C:\PRISM\PRISM.vhd"

# Step 1: Stop the monitoring task
Write-Host "[INFO] Stopping PRISM monitoring..." -ForegroundColor Cyan
try {
    schtasks /change /tn PRISM-Monitor /disable 2>$null | Out-Null
    schtasks /delete /tn PRISM-Monitor /f 2>$null | Out-Null
    schtasks /delete /tn PRISM-Config  /f 2>$null | Out-Null
    Write-Host "[OK] Monitoring stopped" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Could not disable task" -ForegroundColor Yellow
}
Start-Sleep -Seconds 1
Write-Host ""

# Step 2: Close any Explorer windows browsing S: drive
Write-Host "[INFO] Closing Explorer windows on S: drive..." -ForegroundColor Cyan
try {
    $shell = New-Object -ComObject Shell.Application
    $shell.Windows() | Where-Object {
        $_.LocationURL -like "*S%3A*" -or $_.LocationURL -like "file:///S:*"
    } | ForEach-Object {
        try { $_.Quit() } catch {}
    }
    Write-Host "[OK] Explorer windows closed" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Could not close Explorer windows" -ForegroundColor Yellow
}
Start-Sleep -Seconds 1
Write-Host ""

# Step 3: Stop PRISM tray process if running
Write-Host "[INFO] Stopping PRISM tray..." -ForegroundColor Cyan
try {
    Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*PRISM-Tray*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host "[OK] Tray stopped" -ForegroundColor Green
} catch {
    Write-Host "[WARNING] Could not stop tray process" -ForegroundColor Yellow
}
Start-Sleep -Seconds 1
Write-Host ""

# Step 4: Verify S: drive accessibility before detach
Write-Host "[INFO] Verifying S: drive is accessible for detach..." -ForegroundColor Cyan
$sDrive = Get-PSDrive -Name S -ErrorAction SilentlyContinue
if ($sDrive) {
    Write-Host "[INFO] S: drive online, ready to detach" -ForegroundColor Cyan
} else {
    Write-Host "[INFO] S: drive already offline" -ForegroundColor Yellow
}
Start-Sleep -Seconds 1
Write-Host ""

# Step 5: Detach the VHD
Write-Host "[INFO] Detaching virtual disk ($vhdPath)..." -ForegroundColor Cyan
$detachScript = @"
select vdisk file=$vhdPath
detach vdisk noerr
exit
"@

$detachScriptPath = Join-Path $env:TEMP "prism_detach_$(Get-Random).txt"
try {
    $detachScript | Out-File -FilePath $detachScriptPath -Encoding ASCII -Force

    Write-Host "  Running diskpart detach..." -ForegroundColor Gray
    $output = & diskpart /s $detachScriptPath 2>&1

    Write-Host "  Command output:" -ForegroundColor Gray
    foreach($line in $output) {
        if($line.Trim() -ne "") {
            Write-Host "    $line" -ForegroundColor Gray
        }
    }

    Remove-Item -Path $detachScriptPath -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Virtual disk detach command executed" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Detach failed: $_" -ForegroundColor Red
}
Start-Sleep -Seconds 3

Write-Host "[INFO] Removing $($DriveLetter): drive letter..." -ForegroundColor Cyan
& mountvol "$($DriveLetter):" /D 2>&1 | Out-Null
if (-not (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue)) {
    Write-Host "[OK] Drive letter $($DriveLetter): removed" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Drive letter $($DriveLetter): may still be visible - reboot will clear it" -ForegroundColor Yellow
}
Write-Host ""

# Step 6: Delete the VHD file
Write-Host "[INFO] Deleting virtual disk file..." -ForegroundColor Cyan
if(Test-Path $vhdPath) {
    try {
        Write-Host "  File: $vhdPath" -ForegroundColor Gray
        $item = Get-Item $vhdPath -Force
        Write-Host "  Size: $([Math]::Round($item.Length / 1GB, 2)) GB" -ForegroundColor Gray
        Write-Host "  Deleting..." -ForegroundColor Gray

        Remove-Item -Path $vhdPath -Force -ErrorAction Stop

        # Verify deletion
        Start-Sleep -Seconds 1
        if(-not (Test-Path $vhdPath)) {
            Write-Host "[OK] VHD file successfully deleted" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] File still exists after deletion attempt" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERROR] Cannot delete VHD file" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Red
        Write-Host "[INFO] File may be locked. Manual removal needed:" -ForegroundColor Yellow
        Write-Host "  $vhdPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] VHD file not found (already deleted)" -ForegroundColor Green
}
Write-Host ""

# Step 7: Delete PRISM folder
Write-Host "[INFO] Deleting PRISM installation folder..." -ForegroundColor Cyan
if(Test-Path "C:\PRISM") {
    try {
        Write-Host "  Folder: C:\PRISM" -ForegroundColor Gray
        Write-Host "  Deleting contents..." -ForegroundColor Gray

        Remove-Item -Path "C:\PRISM" -Recurse -Force -ErrorAction Stop

        # Verify deletion
        Start-Sleep -Seconds 1
        if(-not (Test-Path "C:\PRISM")) {
            Write-Host "[OK] PRISM folder successfully deleted" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Folder still exists, some files may be locked" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[WARNING] Could not delete all files" -ForegroundColor Yellow
        Write-Host "  Error: $_" -ForegroundColor Red
        Write-Host "[INFO] Manual cleanup may be needed" -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] PRISM folder not found (already deleted)" -ForegroundColor Green
}
Write-Host ""

# Step 8: Remove registry entries
Write-Host "[INFO] Removing registry entries..." -ForegroundColor Cyan
Remove-Item -Path "HKLM:\SOFTWARE\PRISM" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "PRISM-Tray" -ErrorAction SilentlyContinue
Write-Host "[OK] Registry entries removed" -ForegroundColor Green
Write-Host ""

# Final message
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Removal process completed!" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Removal Status:" -ForegroundColor Cyan
Write-Host "  [+] Monitoring task removed" -ForegroundColor Green
Write-Host "  [+] File handles released" -ForegroundColor Green
Write-Host "  [+] Virtual disk detached" -ForegroundColor Green
Write-Host "  [+] Registry entries removed" -ForegroundColor Green

if(-not (Test-Path $vhdPath)) {
    Write-Host "  [+] VHD file deleted" -ForegroundColor Green
} else {
    Write-Host "  [!] VHD file still present (locked)" -ForegroundColor Yellow
}

if(-not (Test-Path "C:\PRISM")) {
    Write-Host "  [+] PRISM folder deleted" -ForegroundColor Green
} else {
    Write-Host "  [!] PRISM folder still present (some files locked)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To verify S: drive removal:" -ForegroundColor Yellow
Write-Host "  1. Open Disk Management (diskmgmt.msc)" -ForegroundColor Yellow
Write-Host "  2. Check if S: drive is no longer listed" -ForegroundColor Yellow
Write-Host ""

if($Wait) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("PRISM removal complete. Click OK to close.", "PRISM Removal", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

exit 0
