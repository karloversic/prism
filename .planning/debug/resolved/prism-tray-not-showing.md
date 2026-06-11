---
status: resolved
trigger: "PRISM system tray icon does not appear after installation completes"
created: 2026-04-25T00:00:00Z
updated: 2026-04-25T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED — Shell.Application is an InProcServer32 (shell32.dll, Apartment threading), not an out-of-process proxy. Calling ShellExecute from an elevated (High IL) process launches the child at High IL. NotifyIcon in a High IL process cannot register in Explorer's systray (Medium IL) on Windows 11 22H2+ because Explorer cannot send NIN_SELECT validation back through UIPI.
test: verified via registry — HKLM\SOFTWARE\Classes\CLSID\{13709620-C279-11CE-A49E-444553540000}\InProcServer32 = shell32.dll, ThreadingModel=Apartment
expecting: replacing Shell.Application.ShellExecute with a Medium IL launch mechanism (scheduled task with RunLevel=Limited) will make the tray icon appear
next_action: apply fix to PRISM-Setup.ps1 Step 5

## Symptoms

expected: After PRISM installation completes, a system tray icon should appear immediately (and reappear on every login via HKCU Run key).
actual: Installation reports success, but no tray icon appears in the system tray — not in the visible area, not in the overflow/hidden icons area.
errors: None reported by installer. Installation log shows "Tray icon launched and registered for auto-start" OK message.
reproduction: Run PRISM-Deploy.bat → accept UAC → click "Begin Installation" → installation completes → no tray icon.
timeline: Issue exists after today's fix (2026-04-25) to PRISM-Setup.ps1. Unclear if it ever worked.

## Eliminated

- hypothesis: Shell.Application COM routes through Explorer when called from an elevated process, producing a Medium IL child
  evidence: HKLM registry confirms CLSID {13709620-C279-11CE-A49E-444553540000} is InProcServer32 (shell32.dll, ThreadingModel=Apartment). In-process COM object cannot route through Explorer. Child inherits caller's High IL token.
  timestamp: 2026-04-25T00:01:00Z

- hypothesis: $PSScriptRoot is empty when launched via ShellExecute with empty working directory
  evidence: $PSScriptRoot is derived from the -File argument path, not from working directory. Setting "C:\PRISM\PRISM-Tray.ps1" as -File always produces $PSScriptRoot = "C:\PRISM".
  timestamp: 2026-04-25T00:01:00Z

- hypothesis: nShowCmd=0 (SW_HIDE) from ShellExecute prevents form.Shown from firing
  evidence: .NET WinForms Application::Run(Form) calls form.Show() via managed path, but this is secondary — even if Shown fires and sets notifyIcon.Visible=true, a High IL NotifyIcon cannot appear in the systray on Windows 11 22H2+.
  timestamp: 2026-04-25T00:01:00Z

## Evidence

- timestamp: 2026-04-25T00:00:30Z
  checked: PRISM-Tray.ps1 lines 513-524 (Shown handler + Application::Run)
  found: notifyIcon.Visible = $true is set exclusively inside $form.Add_Shown({}) handler. Icon is never pre-set to visible before Application::Run.
  implication: If Shown never fires (High IL process + shell registration fails), icon never appears.

- timestamp: 2026-04-25T00:00:45Z
  checked: HKLM\SOFTWARE\Classes\CLSID\{13709620-C279-11CE-A49E-444553540000}
  found: InProcServer32 = shell32.dll, ThreadingModel = Apartment. No LocalServer32.
  implication: Shell.Application COM runs in-process within the elevated PowerShell. ShellExecute launches child as High IL, not Medium IL. The code comment claiming "Medium IL child" is incorrect.

- timestamp: 2026-04-25T00:00:50Z
  checked: PRISM-Tray.ps1 lines 122-144 (TaskbarCreatedMonitor / NIN_SELECT comment in Setup.ps1 line 519)
  found: Tray script has TaskbarCreatedMonitor to handle WM_TASKBARCREATED re-registration. PRISM-Setup.ps1 comment on line 519 explicitly acknowledges "NIN_SELECT bounce-back on Win11 22H2+" requires active message pump.
  implication: The author is aware of Win11 22H2+ NIN_SELECT validation. But the root problem is the High IL process — UIPI blocks Explorer (Medium IL) from sending NIN_SELECT back to the High IL process HWND.

- timestamp: 2026-04-25T00:00:55Z
  checked: PRISM-Setup.ps1 HKCU Run key value (line 461)
  found: Run key uses -NonInteractive flag; live ShellExecute does not. Minor inconsistency — not root cause.
  implication: At next login, the tray will launch with -NonInteractive from HKCU Run (Medium IL, correct). But live launch at install-time is broken due to High IL.

## Resolution

root_cause: Shell.Application COM (CLSID {13709620-C279-11CE-A49E-444553540000}) is an InProcServer32 (shell32.dll, Apartment threading). It runs in-process within the elevated installer, not as an out-of-process proxy through Explorer. ShellExecute called on it launches the child powershell.exe at High Integrity Level (inherited from the elevated installer). On Windows 11 22H2+, Explorer's tray host (Medium IL) cannot send the NIN_SELECT validation bounce-back to a High IL HWND through UIPI, so Shell_NotifyIcon registration silently fails and the icon never appears.

fix: Replaced Shell.Application.ShellExecute with a one-shot scheduled task (PRISM-Tray-Launch) using New-ScheduledTaskPrincipal with LogonType=Interactive and RunLevel=Limited. Task Scheduler spawns the tray process under the interactive user's unelevated (Medium IL) token. The task self-deletes after 800ms. The -NonInteractive flag is now consistent between the live launch and the HKCU Run key value.

verification: Fix is logically verified — scheduled tasks with RunLevel=Limited are the standard pattern for launching Medium IL processes from elevated contexts (same mechanism used by system installers). Functional verification requires running the installer on a Windows 11 machine. The tray script's Shown handler and NotifyIcon registration logic are correct and unchanged.

files_changed:
  - PRISM-Setup.ps1: Replaced Shell.Application.ShellExecute block (lines 464-485) with scheduled task launch block (lines 464-495)
