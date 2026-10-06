#Requires -Version 3.0
# Brute-force: find vpn.dance profile that reaches api2.cursor.sh through local xray.
param(
    [switch]$Quiet,
    [int]$TimeoutSec = 10
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = Split-Path $PSScriptRoot -Parent
$vlessDir = Join-Path $rootDir 'telegram-vless'
$configFile = Join-Path $vlessDir 'config.json'
$xrayExe = Join-Path $vlessDir 'bin\xray.exe'
$pidFile = Join-Path $vlessDir 'xray.pid'
$metaFile = Join-Path $vlessDir 'subscription.meta.json'
$logFile = Join-Path $PSScriptRoot 'vless-probe.log'
$syncScript = Join-Path $PSScriptRoot 'sync-vless-config.ps1'

function Write-ProbeLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try { [IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($true)) } catch {}
    if (-not $Quiet) { Write-Host $msg -ForegroundColor DarkGray }
}

function Test-PortListen([int]$port) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(600, $false) -and $c.Connected) { $c.Close(); return $true }
        $c.Close()
    } catch {}
    return $false
}

function Stop-Xray {
    if (Test-Path $pidFile) {
        $old = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($old -match '^\d+$') { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue }
    }
    Get-Process xray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 350
}

function Test-CurlVia([string]$mode, [int]$port) {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $false }
    $args = if ($mode -eq 'socks') { @('--socks5-hostname', "127.0.0.1:$port") } else { @('-x', "http://127.0.0.1:$port") }
    foreach ($url in @('https://api2.cursor.sh', 'https://www.gstatic.com/generate_204')) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' @args $url --connect-timeout $TimeoutSec --max-time ($TimeoutSec + 3) 2>$null
        if ($code -match '^(200|204|301|302|307|308)$') { return $true }
    }
    return $false
}

function Start-XrayWait {
    $proc = Start-OtmenaNativeProcess -FilePath $xrayExe -Arguments "run -config `"$configFile`"" -WorkingDirectory $vlessDir
    if ($proc -and $proc.Id) { $proc.Id | Out-File $pidFile -Encoding ASCII -Force }
    for ($i = 0; $i -lt 24; $i++) {
        if ($proc -and $proc.HasExited) { return $false }
        if ((Test-PortListen 10808) -and (Test-PortListen 10809)) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return ((Test-PortListen 10808) -and (Test-PortListen 10809))
}

function Get-ProfileCount {
    & $syncScript -Quiet 2>$null | Out-Null
    if (-not (Test-Path $metaFile)) { return 0 }
    try {
        $m = Get-Content $metaFile -Raw | ConvertFrom-Json
        return @($m.profiles).Count
    } catch { return 0 }
}

if (-not (Test-Path $xrayExe)) {
    & (Join-Path $PSScriptRoot 'ensure-xray.ps1') -Quiet | Out-Null
}
if (-not (Test-Path $xrayExe)) {
    Write-Output 'VLESS_PROBE=no-xray'
    exit 1
}

& $syncScript -Quiet 2>$null | Out-Null
$count = Get-ProfileCount
if ($count -le 0) {
    Write-Output 'VLESS_PROBE=no-profiles'
    exit 1
}

Write-ProbeLog "probe $count profiles"

$winnerIdx = -1
$winnerMode = 'socks'
$winnerLabel = ''

for ($i = 0; $i -lt $count; $i++) {
    & $syncScript -Quiet -ProfileIndex $i 2>$null | Out-Null
    if (-not (Test-Path $configFile)) { continue }
    $meta = $null
    try { $meta = Get-Content $metaFile -Raw | ConvertFrom-Json } catch {}
    $label = if ($meta -and $meta.profiles) { $meta.profiles[0] } else { "idx=$i" }
    Write-ProbeLog "try $label"
    Stop-Xray
    if (-not (Start-XrayWait)) {
        Write-ProbeLog '  xray not up'
        continue
    }
    if (Test-CurlVia 'http' 10809) {
        $winnerIdx = $i; $winnerMode = 'http'; $winnerLabel = $label
        Write-ProbeLog '  OK http 10809'
        break
    }
    if (Test-CurlVia 'socks' 10808) {
        $winnerIdx = $i; $winnerMode = 'socks'; $winnerLabel = $label
        Write-ProbeLog '  OK socks 10808'
        break
    }
    Write-ProbeLog '  fail'
}

if ($winnerIdx -lt 0) {
    Write-Output 'VLESS_PROBE=none'
    Write-Output 'WORKING=0'
    Write-ProbeLog 'NO WORKING PROFILE — VPN blocked on this network? Use phone hotspot.'
    exit 1
}

& $syncScript -Quiet -ProfileIndex $winnerIdx 2>$null | Out-Null
Stop-Xray
Start-XrayWait | Out-Null

try {
    $metaObj = Get-Content $metaFile -Raw | ConvertFrom-Json
    $metaObj | Add-Member -NotePropertyName 'cursorMode' -NotePropertyValue $winnerMode -Force
    $metaObj | Add-Member -NotePropertyName 'profileIndex' -NotePropertyValue $winnerIdx -Force
    ($metaObj | ConvertTo-Json -Compress) | Out-File $metaFile -Encoding ASCII -Force
} catch {}

Write-Output ("VLESS_PROFILE={0}" -f $winnerLabel)
Write-Output ("VLESS_MODE={0}" -f $winnerMode)
Write-Output ("VLESS_INDEX={0}" -f $winnerIdx)
Write-Output 'WORKING=1'
Write-ProbeLog "WINNER $winnerLabel mode=$winnerMode"
exit 0
