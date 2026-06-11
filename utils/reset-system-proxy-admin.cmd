@echo off
:: Reset system proxy so only Telegram app uses SOCKS (not Yandex/browser)
netsh winhttp reset proxy >nul 2>&1
netsh winhttp set proxy proxy-server="direct" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0disable-system-proxy.ps1"
