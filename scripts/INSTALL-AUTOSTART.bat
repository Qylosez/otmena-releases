@echo off
chcp 65001 > nul
cd /d "%~dp0"
title Avtozapusk Zapret

echo.
echo  Avtozapusk pri vhode v Windows.
echo  Esli sposob ne rabotaet - avtomat perekljuchaetsya na drugoj.
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Zapusk ot administratora...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\utils\install-autostart.ps1"
pause
