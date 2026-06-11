@echo off
start "" powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0PRISM-Setup.ps1"
