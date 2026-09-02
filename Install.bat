@echo off
REM Double-clickable installer for Windows Explorer / ZIP users
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
pause
