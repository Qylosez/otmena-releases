@echo off
chcp 65001 > nul
cd /d "%~dp0"
title Otmena — YouTube / Discord (admin)

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Zapusk ot imeni administratora...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  Zapusk winws (YouTube / Discord)...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\start-winws.ps1"
timeout /t 3 /nobreak >nul

tasklist /FI "IMAGENAME eq winws.exe" 2>nul | find /I "winws.exe" >nul
if %errorlevel%==0 (
    echo [OK] winws rabotaet — YouTube i Discord dolzhny otkrytsya.
) else (
    echo [X] winws ne zapustilsya. Prover antivirus / WinDivert.
    echo     Papku luchshe derzhat ne v OneDrive, a v C:\Otmena
)
echo.
pause
