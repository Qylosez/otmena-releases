@echo off
chcp 65001 >nul
title Cursor -> Europe
echo Vklyuchayu Cursor cherez tunnel (vpn.dance)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\cursor-europe.ps1"
echo.
echo Zakroj i snova otkroj Cursor, chtoby proksi primenilsya.
pause
