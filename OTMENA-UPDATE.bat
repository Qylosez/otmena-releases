@echo off
chcp 65001 >nul
title Otmena — обновление
cd /d "%~dp0"

echo.
echo  Ставлю обновление через зеркало GitHub. Otmena должна быть запущена
echo  либо этот файл лежит в папке с Otmena.exe.
echo.

if exist "%~dp0utils\bootstrap-update.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\bootstrap-update.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object Net.WebClient).DownloadString('https://cdn.jsdelivr.net/gh/Qylosez/otmena-releases@v1.1.25/utils/bootstrap-update.ps1'))"
)
echo.
pause
