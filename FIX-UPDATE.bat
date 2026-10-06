@echo off
chcp 65001 >nul
title Otmena — поставить обновление (зеркала)
cd /d "%~dp0"

echo.
echo  Скачиваю обновление через зеркала GitHub (gh-proxy / ghfast).
echo  Кнопку «Обновления» в старой версии нажимать не нужно.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\bootstrap-update.ps1"
echo.
pause
