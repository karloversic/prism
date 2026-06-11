@echo off
rem Prefer the wscript shim: it creates the PowerShell console pre-hidden,
rem so launching the installer does not flash a terminal window.
if exist "%~dp0PRISM-Launch.vbs" (
    wscript.exe "%~dp0PRISM-Launch.vbs" user "%~dp0PRISM-Setup.ps1"
) else (
    start "" powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0PRISM-Setup.ps1"
)
