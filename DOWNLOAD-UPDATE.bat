@echo off
chcp 65001 >nul
title Otmena — скачать обновление через туннель
cd /d "%~dp0"

echo.
echo  Сначала в Otmena нажми «Запустить всё» (нужен xray на 10808).
echo  Потом этот файл скачает zip через туннель, минуя блок GitHub.
echo.

set "URL=https://github.com/Qylosez/otmena-releases/releases/latest/download/Otmena-update.zip"
set "OUT=%~dp0Otmena-update.zip"

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [X] Нет curl.exe. Скачай zip с телефона и положи сюда, затем UPDATE-MANUAL.bat
    pause
    exit /b 1
)

echo Пробую SOCKS 127.0.0.1:10808 ...
curl.exe --socks5-hostname 127.0.0.1:10808 -fL --connect-timeout 20 --max-time 180 -A Otmena-Updater -o "%OUT%" "%URL%"
if errorlevel 1 (
    echo Пробую HTTP 127.0.0.1:10809 ...
    curl.exe -x http://127.0.0.1:10809 -fL --connect-timeout 20 --max-time 180 -A Otmena-Updater -o "%OUT%" "%URL%"
)

if not exist "%OUT%" (
    echo.
    echo [X] Не скачалось. Нажми «Запустить всё», подожди 10 сек, повтори.
    echo     Или скачай zip с телефона ^(раздай интернет^) и запусти UPDATE-MANUAL.bat
    pause
    exit /b 1
)

for %%A in ("%OUT%") do set SZ=%%~zA
if %SZ% LSS 200000 (
    echo [X] Файл слишком маленький ^(%SZ% байт^) — это не zip. GitHub отдал заглушку.
    del /f /q "%OUT%" >nul 2>&1
    pause
    exit /b 1
)

echo.
echo [OK] Скачано. Ставлю обновление...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\apply-update.ps1" -InPlace
echo.
pause
