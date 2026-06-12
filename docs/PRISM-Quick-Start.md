# PRISM v1.0.0 - Quick Start

**60-Second Setup Guide**

## What is PRISM?

PRISM = Partition Recycling and Intelligent Storage Management

It creates a 50GB virtual S: drive with automatic capacity monitoring and a `target.marker` file.

## 3 Steps to Deploy

### Step 1: Download Files
Download all **14 files** to the same folder (e.g., D:\PRISM-Deploy):
- PRISM-Deploy.bat
- PRISM-Remove.bat
- PRISM-Troubleshoot.bat
- PRISM.ps1
- PRISM-Deploy.ps1
- PRISM-CreateSDrive.ps1
- PRISM-Stop.ps1
- PRISM-Remove.ps1
- PRISM-Config.ps1
- PRISM-Tray.ps1
- PRISM-License.ps1
- PRISM-Quick-Start.md
- README.md
- S-DRIVE-MARKER-GUIDE.md

### Step 2: Run Deployment
Double-click **PRISM-Deploy.bat**
- Click "Yes" when asked for Administrator
- Enter your license key (purchase at scriptmasters.dev)
- Wait 5 minutes
- Everything is automatic!

### Step 3: Done!
Check Windows File Explorer:
- ✅ S: drive visible (50GB)
- ✅ S:\target.marker exists
- ✅ C:\PRISM folder created

## What Gets Created

- **S: drive** (50GB virtual disk)
- **S:\target.marker** (PRISM marker file)
- **C:\PRISM** (installation folder)
- **C:\PRISM\logs** (daily logs)
- **PRISM-Monitor task** (runs every 8 minutes)

## System Requirements

- Windows 8.1 or higher
- PowerShell 5.0 or higher
- Administrator account
- **55GB free on C: drive** ⚠️
- License key from **scriptmasters.dev** (internet required for activation)

## Troubleshooting

**Need help?**
Run PRISM-Troubleshoot.bat and select option [9] for full diagnostic

**Files corrupted?**
Clear browser cache, disable antivirus, re-download

**Want to uninstall?**
Option 1: Run PRISM-Troubleshoot.bat option [8] (recommended)
Option 2: Run PRISM-Stop.ps1 (right-click, Run as Administrator)

## Next Steps

- Read **README.md** for complete documentation
- Read **S-DRIVE-MARKER-GUIDE.md** for technical details
- Run PRISM-Troubleshoot.bat for diagnostics

---

**Ready?** Double-click PRISM-Deploy.bat! 🚀
