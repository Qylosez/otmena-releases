@echo off
chcp 65001 >nul
title Cursor fix
echo.
echo  Cursor: sbros proksi + perezapusk tunelya...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\cursor-fix.ps1"
echo.
pause
