# CLAUDE.md

## Repository Overview

PRISM (Partition Recycling and Intelligent Storage Management) is a **Windows PowerShell utility** that creates and manages a 50 GB virtual S: drive (VHD-backed), monitors its capacity, and automatically recycles the oldest folders when usage exceeds a configurable threshold. It runs as a scheduled Task Scheduler job and integrates with the system tray.

---

## Stack

- **Language:** PowerShell 5.0+ (5.1+ recommended)
- **Platform:** Windows 8.1+ (Windows 10/11 recommended)
- **System integration:** Task Scheduler, Windows Registry, VHD (Virtual Hard Disk), WinForms (GUI), system tray

---

## Installation

```powershell
# Run as Administrator
.\PRISM-Deploy.bat       # sets up Task Scheduler job + Registry entries
# or directly:
.\PRISM-Deploy.ps1
```

After deploy, PRISM runs automatically every 8 minutes. Files are installed to `C:\PRISM\`.

---

## Scripts

| Script | Purpose |
|---|---|
| `PRISM.ps1` | Main monitoring engine (runs on schedule) |
| `PRISM-Deploy.ps1` | Task Scheduler + Registry setup |
| `PRISM-Deploy.bat` | Batch wrapper for Deploy (handles UAC elevation) |
| `PRISM-CreateSDrive.ps1` | Creates the 50 GB VHD and mounts it as S: |
| `PRISM-Setup.ps1` | Advanced/custom setup |
| `PRISM-Config.ps1` | GUI to adjust capacity threshold and preserve-folders count |
| `PRISM-Tray.ps1` | System tray icon with right-click menu |
| `PRISM-Stop.ps1` | GUI to stop/uninstall monitoring |
| `PRISM-Remove.ps1` | Complete removal (unregisters task, deletes files, cleans registry) |
| `PRISM-Remove.bat` | Menu-driven removal |
| `PRISM-Troubleshoot.bat` | 9-option diagnostic tool |

---

## Architecture

`PRISM.ps1` is the core. It accepts an `-Action` parameter:

| Action | Behaviour |
|---|---|
| `Monitor` | Capacity check → auto-recycle if over threshold |
| `CheckStatus` | Display drive health and usage |
| `CreateMarker` | Create/recreate the `target.marker` sentinel file |
| `Format` | Force recycle regardless of current capacity |

**Monitoring loop (each Task Scheduler trigger):**
1. Check if S: is online; auto-mount VHD via diskpart if not
2. Verify `target.marker` exists on S:; create if missing
3. Read capacity percentage
4. If capacity ≥ threshold (default 95%): sort folders by `LastWriteTime`, delete oldest until capacity drops below threshold (preserving newest N folders)
5. Log all operations to `C:\PRISM\logs\PRISM_YYYY-MM-DD.log`

---

## Registry Configuration

All settings stored under `HKLM:\SOFTWARE\PRISM`:

| Key | Default | Description |
|---|---|---|
| `InstallPath` | `C:\PRISM` | Install directory |
| `LogsPath` | `C:\PRISM\logs` | Log directory |
| `TargetDrive` | `S:` | Monitored drive letter |
| `CapacityThreshold` | `95` | % used before recycling triggers |
| `PreserveFolders` | `5` | Newest N folders to keep during recycle |
| `MonitoringInterval` | `8` | Task Scheduler interval (minutes) |

Adjust via `PRISM-Config.ps1` GUI or edit registry directly.

---

## File Layout After Install

```
C:\PRISM\
├── PRISM.ps1 (+ all supporting scripts)
├── PRISM.vhd              # 50 GB virtual disk image
├── logs/                  # Daily logs: PRISM_YYYY-MM-DD.log
├── format-logs/           # Recycle operation logs
└── backup/                # DB backups (if recovery runs)

S:\
├── target.marker          # Sentinel file (content: "PRISM_TARGET")
└── [managed folders]
```

---

## Requirements

- Windows 8.1+ (10/11 recommended)
- PowerShell 5.0+ (5.1+ recommended)
- Administrator account
- ~55 GB free on C: drive (50 GB for VHD + overhead)
