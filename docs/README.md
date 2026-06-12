# PRISM v1.0.0 - Complete Reference

Partition Recycling and Intelligent Storage Management

## Overview

PRISM is a complete system for:
- Creating and managing a 50GB S: drive (virtual disk)
- Creating and verifying a target.marker file
- Automatic capacity monitoring
- Scheduled operations every 8 minutes
- Complete system logging
- GUI configuration and management

## Features

### Core Features
✅ 50GB virtual S: drive creation
✅ Automatic target.marker file
✅ Capacity monitoring (every 8 minutes)
✅ Automatic logging
✅ Complete error recovery
✅ System integration via Task Scheduler

### GUI Tools
✅ Configuration interface (adjust settings)
✅ Stop/Uninstall interface (GUI-based)
✅ System tray integration (right-click menu)
✅ Diagnostics tool (9 menu options)

### Monitoring
✅ Automatic marker file detection
✅ Auto-recovery of missing marker
✅ Capacity percentage tracking
✅ Daily log files
✅ Operation logs

## Files Included (14 Total)

### Deployment (3 Batch Files)
1. **PRISM-Deploy.bat** - Main deployment (run this!)
2. **PRISM-Remove.bat** - Removal menu
3. **PRISM-Troubleshoot.bat** - 9 diagnostic options

### Engine (1 PowerShell Main Script)
4. **PRISM.ps1** - Monitoring engine

### Configuration (1 PowerShell Script)
5. **PRISM-Deploy.ps1** - Task Scheduler and registry setup

### S: Drive Creation (1 PowerShell Script)
6. **PRISM-CreateSDrive.ps1** - 50GB S: drive creation

### GUI and Management Tools (4 PowerShell Scripts)
7. **PRISM-Stop.ps1** - Stop/Uninstall GUI
8. **PRISM-Remove.ps1** - Complete removal script
9. **PRISM-Config.ps1** - Configuration GUI
10. **PRISM-Tray.ps1** - System tray icon

### Licensing (1 PowerShell Script)
11. **PRISM-License.ps1** - License activation and verification (scriptmasters.dev)

### Documentation (3 Markdown Files)
12. **PRISM-Quick-Start.md** - 60-second setup
13. **README.md** - This file (complete reference)
14. **S-DRIVE-MARKER-GUIDE.md** - Technical details

## Quick Start

### Installation (3 Steps)

**Step 1:** Download all 14 files to same folder
**Step 2:** Double-click PRISM-Deploy.bat
**Step 3:** Enter your license key when prompted, wait 5 minutes, done!

### What Happens Automatically

1. Administrator elevation
2. File validation
3. License activation (enter your scriptmasters.dev key)
4. C:\PRISM folder creation
5. Script copying
6. S: drive creation (50GB)
7. target.marker creation
8. Task Scheduler setup
9. Registry configuration
10. Monitoring starts

## System Requirements

### Minimum
- Windows 8.1 or higher
- PowerShell 5.0 or higher
- Administrator account
- 55GB free on C: drive
- License key from scriptmasters.dev (internet required for activation and periodic verification)

### Recommended
- Windows 10 or higher
- PowerShell 5.1 or higher
- 75GB free on C: drive

## Installation Result

### Folders Created
- C:\PRISM (scripts)
- C:\PRISM\logs (daily logs)
- C:\PRISM\logs\format-logs (operation logs)
- C:\PRISM\backup (backups)

### Virtual Disk
- S: drive (50GB)
- File: C:\PRISM\PRISM.vhd
- Format: NTFS
- Label: PRISM

### Marker File
- Location: S:\target.marker
- Content: PRISM_TARGET
- Auto-created: Yes (if missing)

### System Integration
- Task Scheduler: PRISM-Monitor (every 8 minutes)
- Registry: HKLM:\SOFTWARE\PRISM
- Tray Icon: System integration
- Monitoring: Automatic

## Usage

### Run Monitoring Manually
```powershell
C:\PRISM\PRISM.ps1 -Action Monitor
```

### Check Status
```powershell
C:\PRISM\PRISM.ps1 -Action CheckStatus
```

### Create Marker File
```powershell
C:\PRISM\PRISM.ps1 -Action CreateMarker
```

### Open Configuration GUI
```powershell
C:\PRISM\PRISM-Config.ps1
```

### Open Stop/Uninstall GUI
```powershell
C:\PRISM\PRISM-Stop.ps1
```

### Open System Tray
```powershell
C:\PRISM\PRISM-Tray.ps1
```

## Verification

After deployment, verify:

### Windows File Explorer
- [ ] S: drive visible (50GB)
- [ ] S: shows 50GB total
- [ ] S:\target.marker file exists

### C: Drive
- [ ] C:\PRISM folder exists
- [ ] C:\PRISM\logs has entries
- [ ] C:\PRISM\backup exists

### Task Scheduler
- [ ] PRISM-Monitor task exists
- [ ] Task status: Ready
- [ ] Last run: Recent

### Registry
- [ ] HKLM:\SOFTWARE\PRISM exists

## Troubleshooting

### Problem: "Not enough space"
**Solution:** Free 55GB on C: drive minimum

### Problem: "S: drive not created"
**Solution:** Run PRISM-Troubleshoot.bat [7]

### Problem: "target.marker not found"
**Solution:** Run PRISM.ps1 -Action CreateMarker

### Problem: "Task not running"
**Solution:** Run PRISM-Troubleshoot.bat [3]

### Problem: "Files corrupted"
**Solution:** Clear cache, disable antivirus, re-download

### Problem: Need full diagnostics
**Solution:** Run PRISM-Troubleshoot.bat [9]

### Problem: Want to uninstall
**Solution:** Run PRISM-Troubleshoot.bat [8]

## Logs

### Daily Logs
Located: C:\PRISM\logs\PRISM_YYYY-MM-DD.log

Contains:
- [INFO] - Information messages
- [SUCCESS] - Successful operations
- [WARNING] - Warning messages
- [ERROR] - Error messages

### Format Operation Logs
Located: C:\PRISM\logs\format-logs\recycle_YYYY-MM-DD_HH-mm-ss.log

Contains:
- Partition format operations
- Data recycling operations
- Recovery operations

## Configuration

Edit Registry at: HKLM:\SOFTWARE\PRISM

Keys:
- InstallPath (C:\PRISM)
- LogsPath (C:\PRISM\logs)
- Version (1.0.0)
- TargetDrive (S:)
- CapacityThreshold (95 default)
- PreserveFolders (5 default)
- MonitoringInterval (8 default)

## Support

### Quick Questions
→ Read PRISM-Quick-Start.md

### Technical Details
→ Read S-DRIVE-MARKER-GUIDE.md

### Troubleshooting
→ Run PRISM-Troubleshoot.bat [9]

### Need Help?
→ All documentation answers common issues

## Uninstallation

**Option 1: GUI Method**
1. Run PRISM-Troubleshoot.bat
2. Select [8] Complete Reset
3. Confirm when asked

**Option 2: Manual Method**
1. Delete scheduled task: PRISM-Monitor
2. Delete registry: HKLM:\SOFTWARE\PRISM
3. Delete folder: C:\PRISM
4. Detach S: drive in Disk Management

## Status

✅ All 12 files created
✅ All UTF-8 encoded
✅ S: drive creation implemented
✅ target.marker support added
✅ Complete automation
✅ Full documentation
✅ Production ready

---

**Ready to deploy?** Download all 12 files and run PRISM-Deploy.bat! 🚀
