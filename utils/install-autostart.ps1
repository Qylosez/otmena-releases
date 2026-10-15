#Requires -Version 3.0
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

$flag = Join-Path $PSScriptRoot 'autostart.on'
$stamp = (Get-Date).ToString('s') + [Environment]::NewLine
[IO.File]::WriteAllText($flag, $stamp, (New-Object System.Text.UTF8Encoding $false))

$gameFlag = Join-Path $PSScriptRoot 'game_filter.enabled'
if (Test-Path -LiteralPath $gameFlag) { Remove-Item -LiteralPath $gameFlag -Force }
cmd /c 'net stop zapret' 2>$null | Out-Null
cmd /c 'sc delete zapret' 2>$null | Out-Null

& (Join-Path $PSScriptRoot 'ensure-autostart.ps1')
$ensureCode = $LASTEXITCODE
try {
    & (Join-Path $PSScriptRoot 'launcher.ps1') -Action start
} catch {
    Write-Host "Start now failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
if ($ensureCode -ne 0) { exit $ensureCode }
exit 0
