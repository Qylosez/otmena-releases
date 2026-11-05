@echo off
chcp 65001 >nul
title Cursor — VM / rabochij PK
echo.
echo  Cursor fix (VM):
echo  - perezapusk xray
echo  - socks5 v settings.json
echo  - sistemnyj proksi 127.0.0.1:10809
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\cursor-fix.ps1"
echo.
pause
