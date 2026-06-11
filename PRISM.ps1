param(
    [ValidateSet('Monitor','CheckStatus','Format','CreateMarker')]
    [string]$Action = 'Monitor',
    [string]$LogsPath = "C:\PRISM\logs",
    [string]$TargetDrive = 'S:',
    [int]$CapacityThreshold = 95,
    [int]$PreserveFolders = 5
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Registry-backed settings (HKLM:\SOFTWARE\PRISM) fill any parameter the caller
# did not pass explicitly; an explicit parameter always wins. TargetDrive and
# InstallPath are honored here so editing the registry directly works as documented.
$script:InstallPath = "C:\PRISM"
$regPath = "HKLM:\SOFTWARE\PRISM"
if (Test-Path $regPath) {
    $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if (-not $PSBoundParameters.ContainsKey('TargetDrive')       -and $reg.TargetDrive)                { $TargetDrive       = [string]$reg.TargetDrive }
    if (-not $PSBoundParameters.ContainsKey('CapacityThreshold') -and $null -ne $reg.CapacityThreshold) { $CapacityThreshold = [int]$reg.CapacityThreshold }
    if (-not $PSBoundParameters.ContainsKey('PreserveFolders')   -and $null -ne $reg.PreserveFolders)   { $PreserveFolders   = [int]$reg.PreserveFolders }
    if (-not $PSBoundParameters.ContainsKey('LogsPath')          -and $reg.LogsPath)                   { $LogsPath          = [string]$reg.LogsPath }
    if ($reg.InstallPath) { $script:InstallPath = [string]$reg.InstallPath }
}
$VHDPath = Join-Path $script:InstallPath "PRISM.vhd"

$FormatLogsDirectory = "$LogsPath\format-logs"
$MarkerFile = "${TargetDrive}\target.marker"

function Initialize-Logging {
    if(-not(Test-Path $LogsPath)) {
        New-Item -ItemType Directory -Path $LogsPath -Force | Out-Null
    }
    if(-not(Test-Path $FormatLogsDirectory)) {
        New-Item -ItemType Directory -Path $FormatLogsDirectory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $LogsPath "PRISM_$(Get-Date -Format 'yyyy-MM-dd').log"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue

    $color = @{'INFO'='Cyan'; 'SUCCESS'='Green'; 'WARNING'='Yellow'; 'ERROR'='Red'}
    Write-Host ">> $Message" -ForegroundColor $color[$Level]
}

function Test-DriveLetter {
    param([string]$DriveLetter = 'S:')
    try {
        $driveName = $DriveLetter -replace ':', ''
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-DriveCapacityPercent {
    param([string]$DriveLetter = 'S:')
    try {
        $drive = Get-PSDrive -Name($DriveLetter -replace ':') -ErrorAction Stop
        if($drive) {
            $usedSpace = $drive.Used
            $totalSpace = $drive.Used + $drive.Free
            if($totalSpace -gt 0) {
                $percent = [Math]::Round(($usedSpace / $totalSpace) * 100, 2)
                return $percent
            }
        }
    }
    catch {}
    return -1
}

function Get-DriveInfo {
    param([string]$DriveLetter = 'S:')
    try {
        $drive = Get-PSDrive -Name($DriveLetter -replace ':') -ErrorAction Stop
        if($drive) {
            $usedGB = [Math]::Round($drive.Used / 1GB, 2)
            $totalGB = [Math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
            $freeGB = [Math]::Round($drive.Free / 1GB, 2)
            $percentUsed = [Math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 2)
            return @{Used=$usedGB; Total=$totalGB; Free=$freeGB; PercentUsed=$percentUsed}
        }
    }
    catch {}
    return $null
}

function Mount-PRISMDrive {
    param(
        [string]$VHDPath = "C:\PRISM\PRISM.vhd",
        [string]$DriveLetter = "S"
    )
    if (-not (Test-Path $VHDPath)) {
        Write-Log "VHD file not found: $VHDPath" "ERROR"
        return $false
    }
    $mountScript = @"
select vdisk file=$VHDPath
attach vdisk noerr
select partition 1
assign letter=$DriveLetter noerr
exit
"@
    $scriptPath = Join-Path $env:TEMP "prism_mount.txt"
    $mountScript | Out-File -FilePath $scriptPath -Encoding ASCII -Force
    & diskpart /s $scriptPath 2>&1 | Out-Null
    Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    return Test-DriveLetter "${DriveLetter}:"
}

function Create-MarkerFile {
    param([string]$DriveLetter = 'S:')
    try {
        if(-not(Test-DriveLetter $DriveLetter)) {
            Write-Log "Cannot create marker - drive not found" "ERROR"
            return $false
        }

        $markerPath = "${DriveLetter}\target.marker"
        "PRISM_TARGET" | Out-File -FilePath $markerPath -Encoding UTF8 -Force
        Write-Log "Marker file created: $markerPath" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to create marker file: $_" "ERROR"
        return $false
    }
}

function Invoke-PartitionRecycle {
    param(
        [string]$DriveLetter = 'S:',
        [int]$PreserveFolders = 5,
        [switch]$Force
    )

    Write-Log "Starting partition recycle on $DriveLetter (preserve newest $PreserveFolders folders)" "INFO"

    $topDirs = Get-ChildItem -Path "$DriveLetter\" -Directory -ErrorAction SilentlyContinue
    if (-not $topDirs) {
        Write-Log "No top-level folders found on $DriveLetter - cannot free space via folder deletion" "WARNING"
        return
    }

    $sorted = $topDirs | Sort-Object LastWriteTime
    $totalCount = $sorted.Count

    if ($totalCount -le $PreserveFolders) {
        Write-Log "Folder count ($totalCount) is within preserve limit ($PreserveFolders) - no folders to delete" "INFO"
        return
    }

    $toDelete = $sorted | Select-Object -First ($totalCount - $PreserveFolders)
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $recycleLog = Join-Path $FormatLogsDirectory "recycle_$timestamp.log"
    $recycleLines = @()
    $recycleLines += "PRISM Partition Recycle - $timestamp"
    $recycleLines += "Drive: $DriveLetter"
    $recycleLines += "Folders found: $totalCount"
    $recycleLines += "Folders to delete: $($toDelete.Count)"
    $recycleLines += "Folders to preserve: $PreserveFolders"
    $recycleLines += "---"

    foreach ($dir in $toDelete) {
        if (-not $Force) {
            $currentCap = Get-DriveCapacityPercent -DriveLetter $DriveLetter
            if ($currentCap -ge 0 -and $currentCap -lt $CapacityThreshold) {
                Write-Log "Capacity at $currentCap% - below threshold. Recycle stopped early." "SUCCESS"
                break
            }
        }
        try {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
            $msg = "Deleted folder: $($dir.FullName) (LastWriteTime: $($dir.LastWriteTime))"
            Write-Log $msg "INFO"
            $recycleLines += "[DELETED] $($dir.FullName) | LastWriteTime: $($dir.LastWriteTime)"
        } catch {
            $msg = "Failed to delete folder: $($dir.FullName) - $_"
            Write-Log $msg "WARNING"
            $recycleLines += "[FAILED]  $($dir.FullName) | Error: $_"
        }
    }

    $newCapacity = Get-DriveCapacityPercent -DriveLetter $DriveLetter
    $recycleLines += "---"
    $recycleLines += "Capacity after recycle: $newCapacity%"
    $recycleLines | Out-File -FilePath $recycleLog -Encoding UTF8 -Force
    Write-Log "Recycle complete. New capacity: $newCapacity%. Log: $recycleLog" "SUCCESS"
}

function Set-RunStatus {
    param([string]$Result, [double]$Capacity = -1)
    try {
        $rp = "HKLM:\SOFTWARE\PRISM"
        if (Test-Path $rp) {
            Set-ItemProperty -Path $rp -Name "LastRun"      -Value ([datetime]::Now.ToString("o")) -Force
            Set-ItemProperty -Path $rp -Name "LastResult"   -Value $Result   -Force
            Set-ItemProperty -Path $rp -Name "LastCapacity" -Value $Capacity -Force
        }
    } catch {}
}

Initialize-Logging

switch($Action) {
    'Monitor' {
        Write-Log "=== PRISM Monitoring Cycle Started ===" "INFO"
        Write-Log "Effective config: Threshold=$CapacityThreshold%, PreserveFolders=$PreserveFolders, TargetDrive=$TargetDrive" "INFO"

        if(-not(Test-DriveLetter $TargetDrive)) {
            if(Test-Path $VHDPath) {
                Write-Log "$TargetDrive drive offline - attempting to remount VHD" "WARNING"
                $mounted = Mount-PRISMDrive -VHDPath $VHDPath -DriveLetter ($TargetDrive -replace ':','')
                if(-not $mounted) {
                    Write-Log "Failed to remount VHD - check Disk Management" "ERROR"
                    Write-Log "=== Monitoring Cycle Complete ===" "INFO"
                    Set-RunStatus "DriveError"
                    exit 0
                }
                Write-Log "$TargetDrive drive remounted successfully" "SUCCESS"
            } else {
                Write-Log "$TargetDrive drive not found and no VHD at $VHDPath - use PRISM-CreateSDrive.ps1 to create it" "WARNING"
                Write-Log "=== Monitoring Cycle Complete ===" "INFO"
                Set-RunStatus "DriveError"
                exit 0
            }
        }

        $markerExists = Test-Path $MarkerFile -ErrorAction SilentlyContinue
        if(-not($markerExists)) {
            Write-Log "Marker file not found - creating it" "INFO"
            Create-MarkerFile -DriveLetter $TargetDrive
        }
        else {
            Write-Log "Marker file verified" "SUCCESS"
        }

        Write-Log "Target Drive: $TargetDrive" "INFO"
        $capacityPercent = Get-DriveCapacityPercent -DriveLetter $TargetDrive

        if($capacityPercent -lt 0) {
            Write-Log "Could not read $TargetDrive capacity" "WARNING"
            Write-Log "=== Monitoring Cycle Complete ===" "INFO"
            Set-RunStatus "DriveError"
            exit 0
        }

        Write-Log "Current capacity: $capacityPercent%" "INFO"

        if($capacityPercent -ge $CapacityThreshold) {
            Write-Log "ALERT: Capacity at $capacityPercent% (threshold: $CapacityThreshold%)" "WARNING"
            Invoke-PartitionRecycle -DriveLetter $TargetDrive -PreserveFolders $PreserveFolders
            Set-RunStatus "Recycled" (Get-DriveCapacityPercent -DriveLetter $TargetDrive)
        }
        else {
            Write-Log "Capacity normal: $capacityPercent%" "SUCCESS"
            Set-RunStatus "OK" $capacityPercent
        }

        Write-Log "=== Monitoring Cycle Complete ===" "INFO"
    }
    'CheckStatus' {
        Write-Host ""
        Write-Host "PRISM Status Report" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Target Drive: $TargetDrive"

        if(Test-DriveLetter $TargetDrive) {
            $driveInfo = Get-DriveInfo -DriveLetter $TargetDrive
            if($driveInfo) {
                Write-Host "  Status: Online" -ForegroundColor Green
                Write-Host "  Used: $($driveInfo.Used) GB"
                Write-Host "  Total: $($driveInfo.Total) GB"
                Write-Host "  Free: $($driveInfo.Free) GB"
                Write-Host "  Usage: $($driveInfo.PercentUsed)%"

                if(Test-Path $MarkerFile -ErrorAction SilentlyContinue) {
                    Write-Host "  Marker File: Present" -ForegroundColor Green
                }
                else {
                    Write-Host "  Marker File: MISSING" -ForegroundColor Yellow
                }

                if($driveInfo.PercentUsed -ge $CapacityThreshold) {
                    Write-Host "  WARNING: Above $CapacityThreshold% threshold!" -ForegroundColor Yellow
                }
            }
        }
        else {
            Write-Host "  Status: NOT FOUND" -ForegroundColor Red
            Write-Host "  Solution: Use PRISM-CreateSDrive.ps1 to create S: drive" -ForegroundColor Yellow
        }
        Write-Host ""
    }
    'CreateMarker' {
        Write-Host "Creating target.marker file..." -ForegroundColor Cyan
        if(Create-MarkerFile -DriveLetter $TargetDrive) {
            Write-Host "[OK] Marker file created" -ForegroundColor Green
            exit 0
        }
        else {
            Write-Host "[ERROR] Failed to create marker file" -ForegroundColor Red
            exit 1
        }
    }
    'Format' {
        Write-Log "=== PRISM Format (Forced Recycle) Started ===" "INFO"
        Write-Log "Effective config: PreserveFolders=$PreserveFolders, TargetDrive=$TargetDrive" "INFO"

        if (-not (Test-DriveLetter $TargetDrive)) {
            if (Test-Path $VHDPath) {
                Write-Log "$TargetDrive drive offline - attempting to remount VHD" "WARNING"
                $mounted = Mount-PRISMDrive -VHDPath $VHDPath -DriveLetter ($TargetDrive -replace ':','')
                if (-not $mounted) {
                    Write-Log "Failed to remount VHD - cannot run recycle" "ERROR"
                    exit 1
                }
                Write-Log "$TargetDrive drive remounted successfully" "SUCCESS"
            } else {
                Write-Log "$TargetDrive drive not found and no VHD at $VHDPath" "ERROR"
                exit 1
            }
        }

        Invoke-PartitionRecycle -DriveLetter $TargetDrive -PreserveFolders $PreserveFolders -Force
        Write-Log "=== PRISM Format (Forced Recycle) Complete ===" "INFO"
        exit 0
    }
    default {
        Write-Log "Unknown action: $Action" "ERROR"
        exit 1
    }
}

exit 0
