@echo off
chcp 65001 >nul
title Otmena — proverka
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\run-health-check.ps1"
echo.
echo Polnaya diagnostika: knopka Diagnostika v Otmena (kopiruet v bufer).
pause
