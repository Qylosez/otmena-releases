@echo off
chcp 65001 >nul
title Cursor -> Europe (Poland)
echo Vklyuchayu Cursor cherez tunnel (vyhod Polsha)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\cursor-europe.ps1"
echo.
echo Zakroj i snova otkroj Cursor, chtoby proksi primenilsya.
pause
