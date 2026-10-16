#Requires -Version 3.0
# One shot: vpn.dance xray + SOCKS in Telegram + proxy-dag.ru backup.
param(
    [switch]$Quiet,
    [switch]$SkipXray,
    [switch]$NoList
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

function Test-RemoteTcp([string]$server, [int]$port) {
    if ([string]::IsNullOrWhiteSpace($server) -or $port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($server, $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(2500, $false) -and $client.Connected
        return [bool]$ok
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch {}
    }
}

function Invoke-TelegramInsertScript {
    param([string]$Script, [string[]]$ArgList)
    $out = & $Script @ArgList 2>&1 | Out-String
    $ok = $false
    if ($out -match '(?m)^STATUS=ok\b') { $ok = $true }
    elseif ($out -match '(?m)^STATUS=manual\b') { $ok = $false }
    elseif ($LASTEXITCODE -eq 0) { $ok = $true }
    return @{ Ok = $ok; Text = $out }
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

$exeList = @(Get-TelegramDesktopCandidates)
if ($exeList.Count -gt 0) {
    Write-Output ("TG_EXE={0}" -f $exeList[0])
} else {
    Write-Output 'TG_EXE=missing'
}

$cfgPath = Join-Path $PSScriptRoot 'telegram-mtproto.json'
$mtServer = 'proxy-dag.ru'
$mtPort = 443
if (Test-Path -LiteralPath $cfgPath) {
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.server) { $mtServer = [string]$cfg.server }
        if ($cfg.port) { $mtPort = [int]$cfg.port }
    } catch {}
}
$mtTcp = [int](Test-RemoteTcp $mtServer $mtPort)
Write-Output ("MTPROTO_TCP={0}" -f $mtTcp)
Write-TelegramInsertLog ("probe {0}:{1} tcp={2} xray={3} exe={4}" -f $mtServer, $mtPort, $mtTcp, $xrayOk, $(if ($exeList.Count) { $exeList[0] } else { 'missing' }))

# A dead proxy-dag.ru link becomes the proxy Telegram actually uses, so the
# app never reaches the working local SOCKS. Skip it when the port is closed.
$mt = @{ Ok = $false; Text = '' }
if ($xrayOk -and -not $mtTcp) {
    # Do not disable the active Telegram proxy. That turns off every proxy,
    # including the SOCKS the user just enabled, and the next link is easy to drop.
    Write-Output 'MTPROTO_SKIP=dead'
    Write-TelegramInsertLog 'skip dead proxy-dag, socks only'
} elseif (-not $xrayOk) {
    $pick = $null
    foreach ($p in (Get-OtmenaMtprotoList)) {
        $pServer = [string]$p.server
        $pSecret = [string]$p.secret
        $pPort = 443
        if ($p.port) { $pPort = [int]$p.port }
        if (-not $pServer -or -not $pSecret) { continue }
        if (Test-RemoteTcp $pServer $pPort) { $pick = $p; break }
    }
    if ($pick) {
        $mt = Invoke-TelegramInsertScript -Script (Join-Path $PSScriptRoot 'set-telegram-mtproto.ps1') -ArgList @(
            '-Quiet', '-Server', [string]$pick.server, '-Port', ([string][int]$pick.port), '-Secret', [string]$pick.secret
        )
    }
} else {
    $mt = Invoke-TelegramInsertScript -Script (Join-Path $PSScriptRoot 'set-telegram-mtproto.ps1') -ArgList @('-Quiet')
}
Write-Output ("TG_MTPROTO={0}" -f [int]$mt.Ok)
if (-not $mt.Ok -and $mt.Text) {
    foreach ($line in ($mt.Text -split "`r?`n")) {
        $trim = $line.Trim()
        if ($trim -match '^(MANUAL|MANUAL_SERVER|MANUAL_PORT|MANUAL_SECRET)=') {
            Write-Output $trim
        }
    }
}

$socksOk = 0
if ($xrayOk) {
    $socks = Invoke-TelegramInsertScript -Script (Join-Path $PSScriptRoot 'set-telegram-socks.ps1') -ArgList @('-Quiet', '-Port', "$socksPort")
    $socksOk = [int]$socks.Ok
    if (-not $socks.Ok) {
        foreach ($line in ($socks.Text -split "`r?`n")) {
            $trim = $line.Trim()
            if ($trim -match '^MANUAL_SOCKS=') { Write-Output $trim }
        }
    }
}
Write-Output ("TG_SOCKS={0}" -f $socksOk)
Write-TelegramInsertLog ("socks result ok={0}" -f $socksOk)

if (-not $Quiet) {
    if ($xrayOk -and $socksOk) {
        Write-Host "Telegram SOCKS 127.0.0.1:$socksPort (vpn.dance) + zapas proxy-dag.ru" -ForegroundColor Green
    } elseif ($mt.Ok) {
        Write-Host 'Telegram: dobavlen proxy-dag.ru (xray ne obyazatelen)' -ForegroundColor Green
    } else {
        Write-Host 'Telegram: otkroj Desktop i nazhmi knopku eshchyo raz, ili vvedi proxy vruchnuyu' -ForegroundColor Yellow
    }
}

if (-not $NoList) {
    Show-OtmenaMtprotoList
}

if ($xrayOk -or $mt.Ok -or $socksOk) { exit 0 }
exit 1
