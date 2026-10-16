#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

$flag = Join-Path $PSScriptRoot 'autostart.on'
$stamp = (Get-Date).ToString('s') + [Environment]::NewLine
[IO.File]::WriteAllText($flag, $stamp, (New-Object System.Text.UTF8Encoding $false))

& (Join-Path $PSScriptRoot 'ensure-autostart.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

try {
    & (Join-Path $PSScriptRoot 'launcher.ps1') -Action start -Quiet
} catch {
    Write-Host "Start now failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host 'Done. Autostart = full Start (DS/YT + Telegram + Cursor Europe).'
