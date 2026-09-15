@echo off
chcp 65001 > nul
cd /d "%~dp0"
title Udalenie avtozapuska

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\utils\remove-autostart.ps1"
pause
