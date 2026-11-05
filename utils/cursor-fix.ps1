#Requires -Version 3.0
param(
    [switch]$Quiet,
    [switch]$Hard
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')

Stop-CursorWatch
if ($Hard) {
    taskkill /IM Cursor.exe /F 2>$null | Out-Null
    Start-Sleep -Milliseconds 400
}

Disable-CursorTunnelProxy -Quiet:$Quiet

Write-Host 'Poisk rabochego servera vpn.dance...' -ForegroundColor Cyan
$probe = & (Join-Path $PSScriptRoot 'find-working-vless.ps1') -Quiet 2>&1 | Out-String
$working = $probe -match 'WORKING=1'

if (-not $working) {
    if (-not $Quiet) {
        Write-Host 'Net rabochego profilya na etoj seti.' -ForegroundColor Red
        Write-Host 'Razday internet s TELEFONA (hotspot), potom povtori.' -ForegroundColor Yellow
        Write-Host 'Log: utils\vless-probe.log' -ForegroundColor Gray
    }
    exit 1
}

Start-Sleep -Seconds 1

if (Enable-CursorTunnelProxy -Quiet:$Quiet) {
    $url = Get-CursorProxyUrl
    if (-not $Quiet) {
        Write-Host "Cursor: $url" -ForegroundColor Green
        Write-Host 'POLNOSTYU zakroj Cursor (File -> Exit), otkroj snova.' -ForegroundColor Yellow
    }
    exit 0
}

if (-not $Quiet) {
    Write-Host 'Profil najden, no proksi Cursor ne vklyuchilsya.' -ForegroundColor Red
}
exit 1
