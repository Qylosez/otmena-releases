#Requires -Version 3.0
# Keep system/browser traffic direct. Telegram uses its own SOCKS in app settings only.
$ErrorActionPreference = 'SilentlyContinue'

$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -Type DWord -Force
Remove-ItemProperty -Path $regPath -Name ProxyServer -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name ProxyOverride -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name AutoConfigURL -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $regPath -Name AutoDetect -ErrorAction SilentlyContinue

# WinHTTP is used by some apps/browsers (incl. Yandex in some modes)
netsh winhttp reset proxy | Out-Null
netsh winhttp set proxy proxy-server="direct" | Out-Null
