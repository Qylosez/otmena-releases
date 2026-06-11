#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = Split-Path $PSScriptRoot -Parent
$vlessDir = Join-Path $rootDir 'telegram-vless'
$configFile = Join-Path $vlessDir 'config.json'
$xrayExe = Join-Path $vlessDir 'bin\xray.exe'
$pidFile = Join-Path $vlessDir 'xray.pid'
$logFile = Join-Path $vlessDir 'xray.log'
$socksPort = 10808

function Write-Color($text, $color) {
    Write-Host $text -ForegroundColor $color
}

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(1500, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Stop-LocalXray {
    if (-not (Test-Path $pidFile)) { return }
    $procId = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($procId -match '^\d+$') {
        Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Start-LocalXray {
    if (-not (Test-Path $xrayExe)) {
        Write-Color 'xray not found. Installing...' Yellow
        & (Join-Path $PSScriptRoot 'ensure-xray.ps1')
        if (-not (Test-Path $xrayExe)) {
            Write-Color 'Failed to install xray. Put xray-windows-64.zip in telegram-vless\bin' Red
            exit 1
        }
    }

    Stop-LocalXray

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $xrayExe
    $psi.Arguments = "run -config `"$configFile`""
    $psi.WorkingDirectory = $vlessDir
    $psi.WindowStyle = 'Hidden'
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -Force

    Start-Sleep -Seconds 2
    for ($i = 0; $i -lt 15; $i++) {
        if (Test-PortListen $socksPort) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Open-TelegramSocks([int]$port) {
    . (Join-Path $PSScriptRoot 'telegram-uri.ps1')
    $uri = "tg://socks?server=127.0.0.1&port=$port"
    if (Open-TgUriSafe -Uri $uri -Kind 'socks') {
        Write-Color "Open in Telegram: $uri" Green
    }
}

function Test-SocksTunnel([int]$port) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return $null }
    try {
        $code = & curl.exe -s -o NUL -w '%{http_code}' --socks5-hostname "127.0.0.1:$port" https://api.telegram.org --connect-timeout 12
        return ($code -match '^(200|301|302|307)$')
    } catch {
        return $false
    }
}

function Ensure-ZapretAlt11 {
    $svc = Get-Service -Name zapret -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Running') {
            Start-Service -Name zapret -ErrorAction SilentlyContinue
        }
        if ((Get-Service -Name zapret).Status -eq 'Running') {
            Write-Color 'Zapret service running - Discord/YouTube OK.' Green
            return
        }
    }
    $winws = Get-Process -Name winws -ErrorAction SilentlyContinue
    if ($winws) {
        Write-Color 'Zapret ALT11 (winws) is running - Discord/YouTube OK.' Green
        return
    }
    Write-Color 'Zapret NOT running! Run USTANOVIT-AUTOZAPUSK.bat as Admin.' Red
}

& (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')

Write-Host ''
Write-Color '=== Telegram via your VLESS (Poland) ===' Cyan
Write-Host 'Zapret ALT11 = Discord/YouTube. This script = only Telegram SOCKS.'
Write-Host 'Games: system proxy is OFF - only Telegram app uses SOCKS.'
Write-Host 'Do NOT enable TUN in v2rayTun - it breaks zapret (Discord/YouTube).'
Write-Host 'Use local xray on 127.0.0.1:10808 only.'
Write-Host ''
Ensure-ZapretAlt11
Write-Host ''

if (-not (Test-Path $configFile)) {
    Write-Color "Config missing: $configFile" Red
    exit 1
}

$usePort = $socksPort
$source = 'local xray'

Write-Host 'Starting local xray...'
if (-not (Start-LocalXray)) {
    Write-Color "SOCKS 127.0.0.1:$socksPort not ready. Check $logFile" Red
    exit 1
}
Write-Color "SOCKS ready: 127.0.0.1:$socksPort" Green

$tunnelOk = Test-SocksTunnel $usePort
if ($tunnelOk -eq $true) {
    Write-Color 'Tunnel test OK (api.telegram.org via SOCKS).' Green
} elseif ($tunnelOk -eq $false) {
    Write-Color 'Tunnel test FAILED. Check key/server or try v2rayTun.' Red
}

Open-TelegramSocks $usePort

Write-Host ''
Write-Color '=== V Telegram Desktop ===' Cyan
Write-Host '  Nastrojki -> Prodvinutye -> Tip soedinenija -> Ispolzovat proksi'
Write-Host "  SOCKS5   Server: 127.0.0.1   Port: $usePort"
Write-Host '  Esli ssylka tg:// ne otkrylas - vvedi vruchnuyu.'
Write-Host '  Perezapusti Telegram esli visit Podkljuchenie...'
Write-Host ''
Write-Color "Aktivno: $source, port $usePort" Cyan
Write-Host 'Ostanovit lokalnyj xray: TELEGRAM-VLESS-STOP.bat'
Write-Host 'Ne zakryvaj eto okno poka polzueshsja Telegram (ili derzhi v2rayTun vkljuchennym).'
Write-Host ''
