@echo off
chcp 65001 >nul
title Otmena — obnovlenie vruchnuyu
cd /d "%~dp0"

echo.
echo  Esli knopka Obnovleniya padaet s kodom 1:
echo  1) Skachaj Otmena-update.zip s GitHub Releases
echo  2) Polozhi zip V ETU papku (ryadom s Otmena.exe)
echo  3) Zapusti etot fajl
echo.

if not exist "Otmena-update.zip" (
    echo [X] Net fajla Otmena-update.zip v papke!
    echo     https://github.com/Qylosez/otmena-releases/releases/latest
    echo.
    pause
    exit /b 1
)

echo Obnovlenie iz lokalnogo zip...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\apply-update.ps1" -InPlace
if %errorlevel%==0 (
    echo.
    echo [OK] Obnovleno. Perezapusti Otmena.exe
) else (
    echo.
    echo [X] Oshibka. Smotri utils\update.log
)
echo.
pause
