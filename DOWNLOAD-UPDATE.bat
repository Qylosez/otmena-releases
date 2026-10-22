@echo off
chcp 65001 >nul
title Otmena — скачать обновление
cd /d "%~dp0"

echo.
echo  Скачиваю zip через зеркала. Если не выйдет — через туннель Otmena.
echo  Если xray ещё не поднят: сначала в Otmena нажми «Запустить всё».
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\bootstrap-update.ps1"
echo.
pause
