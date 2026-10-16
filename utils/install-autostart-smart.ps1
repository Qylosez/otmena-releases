#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

$flag = Join-Path $PSScriptRoot 'autostart.on'
$stamp = (Get-Date).ToString('s') + [Environment]::NewLine
[IO.File]::WriteAllText($flag, $stamp, (New-Object System.Text.UTF8Encoding $false))

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $gameFlag = Join-Path $PSScriptRoot 'game_filter.enabled'
    if (Test-Path -LiteralPath $gameFlag) { Remove-Item -LiteralPath $gameFlag -Force }
    cmd /c 'net stop zapret' 2>$null | Out-Null
    cmd /c 'sc delete zapret' 2>$null | Out-Null
}

& (Join-Path $PSScriptRoot 'ensure-autostart.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

try {
    & (Join-Path $PSScriptRoot 'launcher.ps1') -Action start
} catch {
    Write-Host "Start now failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
exit 0
