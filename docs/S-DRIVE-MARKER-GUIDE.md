# PRISM v1.0.0 - S: Drive & Marker File Guide

## What This Bundle Does

**Creates a 50GB S: partition with target.marker file automatically during deployment**

This is the MAIN TASK - creating S: drive with all necessary setup for PRISM monitoring.

## S: Drive Creation Details

### Virtual Disk Specifications

```
S: Drive (50GB)
├── File: C:\PRISM\PRISM.vhd
├── Size: 50 GB
├── File System: NTFS
├── Label: PRISM
├── Drive Letter: S:
└── Accessible: Yes (mounted automatically)
```

### How S: Drive Creation Works

**Step 1: Disk Space Validation**
- Checks C: drive for 55GB free space
- 50GB for S: drive + 5GB buffer
- Fails gracefully if insufficient space

**Step 2: Virtual Disk Creation**
- Creates VHD file at C:\PRISM\PRISM.vhd
- Size: 50GB (pre-allocated)
- Format: VHD (Virtual Hard Disk)

**Step 3: Virtual Disk Mounting**
- Uses Windows diskpart tool
- Attaches VHD to system
- Mounts as S: drive letter
- Automatic on every boot (after creation)

**Step 4: Formatting**
- File system: NTFS
- Label: PRISM
- Quick format (minimal time)
- Ready for use immediately

## Target Marker File

### Marker File Details

```
S:\target.marker
├── Location: S: drive root
├── File type: Text file
├── Content: PRISM_TARGET
├── Size: ~15 bytes
└── Purpose: Mark drive as PRISM target
```

### Marker File Creation

**Automatic Creation:**
- Created by PRISM-Deploy.bat after S: drive ready
- Writes "PRISM_TARGET" to file
- Uses UTF-8 encoding
- Non-destructive file (can be recreated)

**Auto-Recovery:**
- PRISM.ps1 checks marker on each cycle
- Creates marker if missing (auto-recovery)
- Logs all marker operations
- Reports status in daily logs

**Manual Creation:**
- Can be created manually via:
  ```powershell
  PRISM.ps1 -Action CreateMarker
  ```
- Or manually:
  ```cmd
  echo PRISM_TARGET > S:\target.marker
  ```

## Deployment Process

### Complete Workflow

```
1. Download all 12 files → Same folder
2. Run PRISM-Deploy.bat → Auto-elevates
3. Auto: File validation ✓
4. Auto: Folder creation (C:\PRISM) ✓
5. Auto: Script copying ✓
6. Auto: S: Drive creation ✓ (PRISM-CreateSDrive.ps1)
7. Auto: target.marker creation ✓
8. Auto: Task Scheduler setup ✓
9. Auto: Registry configuration ✓
10. Auto: Monitoring started ✓
11. Result: S: drive (50GB) + marker ready ✓
```

### What PRISM-CreateSDrive.ps1 Does

**Purpose:** Create 50GB S: drive

**Execution:**
1. Validates 55GB free on C: drive
2. Creates VHD file (C:\PRISM\PRISM.vhd)
3. Mounts VHD as S: drive
4. Formats with NTFS
5. Returns success/failure status

**Called by:**
- PRISM-Deploy.bat (automatic)
- PRISM-Troubleshoot.bat [7] (manual option)

**Parameters:**
- SizeGB: 100 (50GB drive)
- DriveLetter: S (mount as S:)

### What PRISM-Deploy.bat Does

**S: Drive Creation Part:**
```batch
powershell -File PRISM-CreateSDrive.ps1
```

**Marker File Creation Part:**
```batch
echo PRISM_TARGET > S:\target.marker
```

**Automatic Steps:**
1. Calls PRISM-CreateSDrive.ps1
2. Waits for S: drive to be ready
3. Creates S:\target.marker
4. Verifies marker file exists
5. Reports results

## Monitoring with S: Drive

### PRISM.ps1 Monitoring

**On Each Cycle (Every 8 Minutes):**
1. Check if S: drive exists
2. Check if S:\target.marker exists
3. Create marker if missing (auto-recovery)
4. Log status to C:\PRISM\logs
5. Monitor capacity percentage
6. Report alerts if threshold exceeded
7. Continue indefinitely

**Marker Verification:**
- Detects missing marker automatically
- Creates marker if not found
- Logs all marker operations
- Reports "Marker file verified"

### Logging

**Location:** C:\PRISM\logs\PRISM_YYYY-MM-DD.log

**Log Entries:**
```
[2026-01-23 20:05:32] [INFO] === PRISM Monitoring Cycle Started ===
[2026-01-23 20:05:32] [SUCCESS] Marker file verified
[2026-01-23 20:05:32] [INFO] Target Drive: S:
[2026-01-23 20:05:32] [INFO] Current capacity: 12%
[2026-01-23 20:05:32] [SUCCESS] Capacity normal: 12%
[2026-01-23 20:05:32] [INFO] === Monitoring Cycle Complete ===
```

## System Requirements for S: Drive

### Disk Space
- **CRITICAL:** 55GB free on C: drive
- 50GB for S: drive
- 5GB buffer for operations
- Less than this = deployment fails

### System
- Windows 8.1+
- PowerShell 5.0+
- Administrator account
- Disk Management tools available

### Virtual Disk Support
- Supported on all modern Windows versions
- VHD format fully supported
- Automatic mounting on boot
- No special drivers needed

## Verification Steps

### After Deployment - Check S: Drive

**Windows File Explorer:**
```
✓ S: drive visible
✓ S: shows 50GB capacity
✓ S:\target.marker file present
```

**Command Line Check:**
```powershell
# Check drive exists
Get-PSDrive S

# Check marker file
Test-Path S:\target.marker

# View marker content
Get-Content S:\target.marker
```

**Expected Output:**
```
PRISM_TARGET
```

### Check Monitoring Status

**Run Diagnostic:**
```batch
PRISM-Troubleshoot.bat [9]
```

**Expected Results:**
```
[OK] S: drive exists
[OK] S:\target.marker exists
[OK] PRISM-Monitor task exists
[OK] Registry entries exist
[OK] Full diagnostic PASS
```

## Troubleshooting S: Drive

### Issue: "Not enough free space"
**Cause:** Less than 55GB available on C: drive
**Solution:**
1. Free up space on C: drive
2. Run PRISM-Troubleshoot.bat [7]
3. Or delete C:\PRISM and retry deployment

### Issue: "S: drive not created"
**Cause:** PRISM-CreateSDrive.ps1 failed
**Solution:**
1. Check C: drive has 55GB free
2. Run PRISM-Troubleshoot.bat [7]
3. Check logs: C:\PRISM\logs
4. Retry PRISM-Deploy.bat

### Issue: "target.marker not found"
**Cause:** Marker creation failed
**Solution:**
1. Verify S: drive mounted
2. Check S: drive permissions
3. Run: PRISM.ps1 -Action CreateMarker
4. Or manually: echo PRISM_TARGET > S:\target.marker

### Issue: "S: drive unmounts after reboot"
**Cause:** VHD not configured for auto-mount
**Solution:**
1. Open Disk Management
2. Right-click VHD file
3. Select "Attach"
4. Check "Auto-mount"

### Issue: "Monitoring can't find S: drive"
**Cause:** Drive unmounted or detached
**Solution:**
1. Verify S: drive in File Explorer
2. Run: Get-PSDrive S
3. If missing, run PRISM-Troubleshoot.bat [7]
4. Check C:\PRISM\logs for errors

## Technical Details

### VHD File Properties

**File:** C:\PRISM\PRISM.vhd
- **Type:** VHD (Virtual Hard Disk)
- **Size:** 50 GB (expandable)
- **Format:** Expandable (dynamic, grows as needed)
- **Encryption:** None
- **Compression:** None
- **Location:** C:\PRISM folder
- **Accessible:** Read/Write

### Diskpart Commands Used

```batch
create vdisk file=C:\PRISM\PRISM.vhd maximum=51200 type=expandable
attach vdisk
create partition primary
format fs=NTFS label=PRISM quick
assign letter=S
exit
```

### NTFS Formatting

- **File System:** NTFS (New Technology File System)
- **Label:** PRISM
- **Allocation Unit:** 4KB (default)
- **Security:** Standard NTFS permissions
- **Quick Format:** Yes (faster creation)

## Best Practices

### S: Drive Management
- Do NOT delete C:\PRISM\PRISM.vhd manually
- Do NOT move VHD file
- Do NOT use 3rd-party disk utilities
- Use Disk Management or Windows tools only

### Marker File Management
- Do NOT delete S:\target.marker manually
- PRISM will auto-recreate if missing
- File is non-critical (auto-recovery enabled)
- Can be manually recreated at any time

### Monitoring
- Keep PRISM-Monitor task enabled
- Check logs regularly (C:\PRISM\logs)
- Run PRISM-Troubleshoot.bat occasionally
- Verify S: drive exists every month

## Advanced Usage

### Manual S: Drive Creation

If PRISM-Deploy.bat doesn't work:
```powershell
powershell -File PRISM-CreateSDrive.ps1
```

### Manual Marker Creation

If marker file is missing:
```powershell
PRISM.ps1 -Action CreateMarker
```

### Check Status Anytime

```powershell
PRISM.ps1 -Action CheckStatus
```

### Run Monitoring Manually

```powershell
PRISM.ps1 -Action Monitor
```

## Recovery Procedures

### If S: Drive Disappears

1. Check in Disk Management
2. Virtual Disk might be detached
3. Right-click → Attach VHD
4. Select: C:\PRISM\PRISM.vhd
5. S: drive will reappear

### If Marker File Missing

1. PRISM auto-recreates it
2. Or manual: PRISM.ps1 -Action CreateMarker
3. Or manually: echo PRISM_TARGET > S:\target.marker

### If Monitoring Stops

1. Check task: PRISM-Troubleshoot.bat [2]
2. Restart task: PRISM-Troubleshoot.bat [3]
3. Check logs: C:\PRISM\logs

### Complete Recovery

1. Run: PRISM-Troubleshoot.bat [8]
2. Confirms complete reset
3. Deletes everything
4. Run PRISM-Deploy.bat to reinstall

## Summary

✅ **S: Drive:** 50GB VHD at C:\PRISM\PRISM.vhd
✅ **Marker File:** S:\target.marker (PRISM_TARGET)
✅ **Automatic:** All created during deployment
✅ **Monitoring:** Continuous checking every 8 minutes
✅ **Recovery:** Auto-creates missing files
✅ **Logging:** Complete operation logging

**Status: PRODUCTION READY!** 🚀

---

Download all 12 files and run PRISM-Deploy.bat to create 50GB S: drive with target.marker!
