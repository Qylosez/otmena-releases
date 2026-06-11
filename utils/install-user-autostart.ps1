#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

$rootDir = Split-Path $PSScriptRoot -Parent
$startupDir = [Environment]::GetFolderPath('Startup')
$linkPath = Join-Path $startupDir 'Otmena.lnk'
$ps = (Get-Command powershell.exe).Source
$target = Join-Path $PSScriptRoot 'start-all-quiet.ps1'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($linkPath)
$shortcut.TargetPath = $ps
$shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
$shortcut.WorkingDirectory = $rootDir
$shortcut.WindowStyle = 7
$shortcut.Description = 'Otmena: DS/YT + Telegram'
$shortcut.Save()

Write-Host "Startup shortcut: $linkPath"

& (Join-Path $PSScriptRoot 'ensure-xray.ps1') -Quiet | Out-Null
& (Join-Path $PSScriptRoot 'telegram-vless-daemon.ps1') -Quiet | Out-Null
& (Join-Path $PSScriptRoot 'set-telegram-socks.ps1') -Quiet 2>$null | Out-Null
Write-Host 'Done. Telegram should ask to enable SOCKS 127.0.0.1:10808.'
