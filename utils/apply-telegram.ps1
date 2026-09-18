#Requires -Version 3.0
# One shot: vpn.dance xray + SOCKS in Telegram + proxy-dag.ru backup.
param(
    [switch]$Quiet,
    [switch]$SkipXray
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = Split-Path $PSScriptRoot -Parent
$socksPort = 10808

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(800, $false) -and $c.Connected
        $c.Close()
        return $ok
    } catch { return $false }
}

$xrayOk = [int](Test-PortListen $socksPort)
if (-not $SkipXray -and -not $xrayOk) {
    & (Join-Path $PSScriptRoot 'telegram-vless-daemon.ps1') -Quiet | Out-Null
    for ($i = 0; $i -lt 16; $i++) {
        if (Test-PortListen $socksPort) { $xrayOk = 1; break }
        Start-Sleep -Milliseconds 250
    }
}

Write-Output ("XRAY={0}" -f $xrayOk)

& (Join-Path $PSScriptRoot 'set-telegram-mtproto.ps1') -Quiet | Out-Null
$mtCode = $LASTEXITCODE
Write-Output ("TG_MTPROTO={0}" -f [int]($mtCode -eq 0))

$socksOk = 0
if ($xrayOk) {
    & (Join-Path $PSScriptRoot 'set-telegram-socks.ps1') -Quiet -Port $socksPort | Out-Null
    $socksOk = [int]($LASTEXITCODE -eq 0)
}
Write-Output ("TG_SOCKS={0}" -f $socksOk)

if (-not $Quiet) {
    if ($xrayOk -and $socksOk) {
        Write-Host "Telegram SOCKS 127.0.0.1:$socksPort (vpn.dance) + zapas proxy-dag.ru" -ForegroundColor Green
    } elseif ($mtCode -eq 0) {
        Write-Host 'Telegram: dobavlen proxy-dag.ru (xray ne obyazatelen)' -ForegroundColor Green
    } else {
        Write-Host 'Telegram: otkroj Desktop i nazhmi knopku eshchyo raz, ili vvedi proxy vruchnuyu' -ForegroundColor Yellow
    }
}

if ($xrayOk -or ($mtCode -eq 0) -or $socksOk) { exit 0 }
exit 1
