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
$shortcut.Description = 'Otmena: DS/YT + Telegram + Cursor Europe'
$shortcut.Save()

Write-Host "Startup shortcut: $linkPath"

& (Join-Path $PSScriptRoot 'install-watchdog.ps1') | Out-Null
try {
    & (Join-Path $PSScriptRoot 'launcher.ps1') -Action start -Quiet
} catch {
    Write-Host "Start now failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host 'Done. Autostart = full Start (DS/YT + Telegram + Cursor Europe).'
