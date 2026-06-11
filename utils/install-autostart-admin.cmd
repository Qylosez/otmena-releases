@echo off
chcp 65001 > nul
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-autostart.ps1" > "%~dp0autostart-install.log" 2>&1
