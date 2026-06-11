param(
    [int]$SizeGB = -1,
    [string]$DriveLetter = "S"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

if ($SizeGB -le 0) {
    $regSize = (Get-ItemProperty -Path "HKLM:\SOFTWARE\PRISM" -Name "DriveSize" -ErrorAction SilentlyContinue).DriveSize
    $SizeGB = if ($null -ne $regSize) { [int]$regSize } else { 50 }
}

Write-Host ""
Write-Host "Creating S: Drive - ${SizeGB}GB Virtual Disk" -ForegroundColor Cyan
Write-Host ""

try {
    $existingDrive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if($existingDrive) {
        Write-Host "[WARNING] $($DriveLetter): drive already exists and is mounted" -ForegroundColor Yellow
        Write-Host "Skipping creation" -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }

    $cDrive = Get-PSDrive -Name C
    $availableGB = [Math]::Round($cDrive.Free / 1GB, 2)

    Write-Host "Available space on C: drive: $availableGB GB" -ForegroundColor Yellow
    Write-Host ""

    if($availableGB -lt ($SizeGB + 5)) {
        Write-Host "[ERROR] Not enough free space on C: drive" -ForegroundColor Red
        Write-Host "Required: $($SizeGB + 5) GB, Available: $availableGB GB" -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    $vhdPath = "C:\PRISM\PRISM.vhd"

    # Check if VHD file already exists (partial/corrupted from previous attempt)
    if(Test-Path $vhdPath) {
        Write-Host "[WARNING] Existing VHD file found at $vhdPath" -ForegroundColor Yellow
        Write-Host "Attempting to detach and remove..." -ForegroundColor Yellow
        Write-Host ""

        # Try to detach the VHD if it's still attached
        $detachScript = @"
select vdisk file=$vhdPath
detach vdisk
exit
"@
        $detachScriptPath = Join-Path $env:TEMP "prism_detach_$(Get-Random).txt"
        $detachScript | Out-File -FilePath $detachScriptPath -Encoding ASCII -Force
        & diskpart /s $detachScriptPath 2>&1 | Out-Null
        Remove-Item -Path $detachScriptPath -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        # Remove the corrupted file
        try {
            Remove-Item -Path $vhdPath -Force
            Write-Host "[OK] Removed corrupted VHD file" -ForegroundColor Green
            Write-Host ""
        }
        catch {
            Write-Host "[ERROR] Cannot remove existing VHD file" -ForegroundColor Red
            Write-Host "[ERROR] File is in use or locked" -ForegroundColor Red
            Write-Host "[INFO] Close File Explorer and Disk Management, then retry" -ForegroundColor Yellow
            Write-Host ""
            exit 1
        }
    }

    if (-not (Test-Path "C:\PRISM")) {
        New-Item -ItemType Directory -Path "C:\PRISM" -Force | Out-Null
    }

    Write-Host "Creating virtual disk: $($SizeGB)GB..." -ForegroundColor Cyan
    Write-Host ""

    # Create diskpart script file with optimized settings
    $diskpartScriptPath = Join-Path $env:TEMP "prism_create_$(Get-Random).txt"
    $maximumSize = $SizeGB * 1024
    $diskpartScript = @"
create vdisk file=$vhdPath maximum=$maximumSize type=expandable
attach vdisk
create partition primary
format fs=NTFS label=PRISM quick
assign letter=$DriveLetter
exit
"@

    Write-Host "Running diskpart (this may take 30-60 seconds)..." -ForegroundColor Yellow
    Write-Host ""

    # Write script to file
    $diskpartScript | Out-File -FilePath $diskpartScriptPath -Encoding ASCII -Force

    # Execute diskpart with the script file
    $output = & diskpart /s $diskpartScriptPath 2>&1

    Write-Host "Waiting for drive to stabilize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    Write-Host ""

    # Check for errors in output
    $errorLines = @()
    foreach($line in $output) {
        if($line -match "error|failed|cannot" -and $line -notmatch "errors: 0") {
            $errorLines += $line
        }
    }

    if($errorLines.Count -gt 0) {
        Write-Host "[ERROR] Diskpart reported errors:" -ForegroundColor Red
        foreach($line in $errorLines) {
            Write-Host "  $line" -ForegroundColor Red
        }
        Write-Host "[ERROR] Failed to create virtual disk" -ForegroundColor Red
        Write-Host ""

        # Cleanup script file
        Remove-Item -Path $diskpartScriptPath -Force -ErrorAction SilentlyContinue
        exit 1
    }

    # Verify drive was created
    $driveCheckCount = 0
    $newDrive = $null
    while($driveCheckCount -lt 5) {
        $newDrive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
        if($newDrive) {
            break
        }
        Start-Sleep -Seconds 1
        $driveCheckCount++
    }

    if($newDrive) {
        $driveSize = [Math]::Round(($newDrive.Used + $newDrive.Free) / 1GB, 2)
        Write-Host "[OK] Virtual disk created successfully" -ForegroundColor Green
        Write-Host ""
        Write-Host "Drive Details:" -ForegroundColor Cyan
        Write-Host "  Drive Letter: $($DriveLetter):" -ForegroundColor Green
        Write-Host "  Size: $driveSize GB" -ForegroundColor Green
        Write-Host "  Path: $vhdPath" -ForegroundColor Green
        Write-Host "  Format: NTFS" -ForegroundColor Green
        Write-Host ""
        Write-Host "Status: Ready for PRISM installation" -ForegroundColor Green
        Write-Host ""

        # Cleanup script file
        Remove-Item -Path $diskpartScriptPath -Force -ErrorAction SilentlyContinue
        exit 0
    }
    else {
        Write-Host "[ERROR] Virtual disk was not mounted after creation" -ForegroundColor Red
        Write-Host "[ERROR] Please check Disk Management" -ForegroundColor Red
        Write-Host ""
        Write-Host "[INFO] Solutions:" -ForegroundColor Yellow
        Write-Host "  1. Open Disk Management (diskmgmt.msc)" -ForegroundColor Yellow
        Write-Host "  2. Look for uninitialized disk (should be ${SizeGB}GB)" -ForegroundColor Yellow
        Write-Host "  3. Right-click > Bring Online" -ForegroundColor Yellow
        Write-Host "  4. Then assign drive letter S:" -ForegroundColor Yellow
        Write-Host ""

        # Cleanup script file
        Remove-Item -Path $diskpartScriptPath -Force -ErrorAction SilentlyContinue
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Exception: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}
