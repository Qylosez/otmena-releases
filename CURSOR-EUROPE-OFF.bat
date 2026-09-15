@echo off
chcp 65001 >nul
title Cursor -> Europe OFF
echo Vyklyuchayu tunnel dlya Cursor (pryamoe soedinenie)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\cursor-europe.ps1" -Off
echo.
echo Zakroj i snova otkroj Cursor.
pause
