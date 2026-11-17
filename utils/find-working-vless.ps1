#Requires -Version 3.0
# Brute-force: find vpn.dance profile that reaches api2.cursor.sh through local xray.
param(
    [switch]$Quiet,
    [int]$TimeoutSec = 4
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
    $script:LastCurlCode = 'nocurl'
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $false }
    $proxyArgs = if ($mode -eq 'socks') { @('--socks5-hostname', "127.0.0.1:$port") } else { @('-x', "http://127.0.0.1:$port") }
    $code = & curl.exe -s -o NUL -w '%{http_code}' @proxyArgs 'https://api2.cursor.sh' --connect-timeout $TimeoutSec --max-time ($TimeoutSec + 2) 2>$null
    $script:LastCurlCode = [string]$code
    return ($code -match '^(200|204|301|302|307|308)$')
}

function Test-RemoteTcpQuick([string]$address, [int]$port) {
    if (-not $address -or $port -le 0) { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($address, $port, $null, $null)
        return ($iar.AsyncWaitHandle.WaitOne(1500, $false) -and $client.Connected)
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch {}
    }
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

& $syncScript -Quiet -Offline 2>$null | Out-Null
$count = Get-ProfileCount
if ($count -le 0) {
    Write-Output 'VLESS_PROBE=no-profiles'
    exit 1
}

Write-ProbeLog "probe $count profiles"

$fullConfig = Join-Path $vlessDir 'config.probe-backup.json'
$fullMeta = Join-Path $vlessDir 'subscription.meta.probe-backup.json'
Copy-Item -LiteralPath $configFile -Destination $fullConfig -Force
if (Test-Path -LiteralPath $metaFile) {
    Copy-Item -LiteralPath $metaFile -Destination $fullMeta -Force
}
$deadline = (Get-Date).AddSeconds(50)
$winnerIdx = -1
$winnerMode = 'socks'
$winnerLabel = ''

try {
    Stop-Xray
    if ((Start-XrayWait) -and (Test-CurlVia 'http' 10809)) {
        Write-Output 'VLESS_PROFILE=full'
        Write-Output 'VLESS_MODE=http'
        Write-Output 'WORKING=1'
        Write-ProbeLog 'full config already live'
        exit 0
    }
    Write-ProbeLog ("full config not live http={0}" -f $script:LastCurlCode)

    # The full config already tried profile 0. Retrying it burns the whole
    # deadline on one dead address, so the other country is never tested.
    $tryOrder = New-Object System.Collections.Generic.List[int]
    $metaAll = $null
    try { $metaAll = Get-Content $metaFile -Raw | ConvertFrom-Json } catch {}
    $profileList = @()
    if ($metaAll -and $metaAll.profiles) { $profileList = @($metaAll.profiles) }
    $primaryAddr = ''
    if ($profileList.Count -gt 0 -and [string]$profileList[0] -match '^([^:]+):') { $primaryAddr = $Matches[1] }
    $otherAddr = New-Object System.Collections.Generic.List[int]
    $sameAddr = New-Object System.Collections.Generic.List[int]
    for ($i = 1; $i -lt $count; $i++) {
        $addr = ''
        if ($i -lt $profileList.Count -and [string]$profileList[$i] -match '^([^:]+):') { $addr = $Matches[1] }
        if ($primaryAddr -and $addr -and ($addr -ne $primaryAddr)) { $otherAddr.Add($i) } else { $sameAddr.Add($i) }
    }
    foreach ($i in $otherAddr) { $tryOrder.Add($i) }
    foreach ($i in $sameAddr) { $tryOrder.Add($i) }
    Write-ProbeLog ("order other-address-first " + ($tryOrder -join ','))

    foreach ($i in $tryOrder) {
        if ((Get-Date) -gt $deadline) {
            Write-ProbeLog 'deadline, stop scanning'
            break
        }
        & $syncScript -Quiet -Offline -ProfileIndex $i 2>$null | Out-Null
        if (-not (Test-Path $configFile)) { continue }
        $meta = $null
        try { $meta = Get-Content $metaFile -Raw | ConvertFrom-Json } catch {}
        $label = if ($meta -and $meta.profiles) { $meta.profiles[0] } else { "idx=$i" }
        Write-ProbeLog "try $label"
        $udpProfile = $label -match '/hysteria'
        $tcp = -1
        if (-not $udpProfile -and $label -match '^([^:]+):(\d+)/') {
            $tcp = [int](Test-RemoteTcpQuick $Matches[1] ([int]$Matches[2]))
        }
        if ($tcp -eq 0) {
            Write-ProbeLog '  fail tcp=0 http=skip'
            continue
        }
        $savedTimeout = $TimeoutSec
        if ($udpProfile -and $TimeoutSec -lt 8) { $TimeoutSec = 8 }
        Stop-Xray
        if (-not (Start-XrayWait)) {
            $TimeoutSec = $savedTimeout
            Write-ProbeLog ("  xray not up tcp={0}" -f $tcp)
            continue
        }
        if (Test-CurlVia 'http' 10809) {
            $winnerIdx = $i; $winnerMode = 'http'; $winnerLabel = $label
            Write-ProbeLog ("  OK http={0} tcp={1}" -f $script:LastCurlCode, $tcp)
            break
        }
        $why = ''
        if ($script:LastCurlCode -eq '403') { $why = ' region-block' }
        $TimeoutSec = $savedTimeout
        Write-ProbeLog ("  fail http={0} tcp={1}{2}" -f $script:LastCurlCode, $tcp, $why)
    }

    if ($winnerIdx -lt 0) {
        if (Test-Path -LiteralPath $fullConfig) {
            Copy-Item -LiteralPath $fullConfig -Destination $configFile -Force
        } else {
            & $syncScript -Quiet -Offline 2>$null | Out-Null
        }
        if (Test-Path -LiteralPath $fullMeta) {
            Copy-Item -LiteralPath $fullMeta -Destination $metaFile -Force
        }
        Stop-Xray
        Start-XrayWait | Out-Null
        Write-Output 'VLESS_PROBE=none'
        Write-Output 'WORKING=0'
        Write-ProbeLog 'NO WORKING PROFILE — restored full config'
        exit 1
    }

    & $syncScript -Quiet -Offline -ProfileIndex $winnerIdx 2>$null | Out-Null
    Stop-Xray
    if (-not (Start-XrayWait)) {
        Write-Output 'VLESS_PROBE=none'
        Write-Output 'WORKING=0'
        Write-ProbeLog 'winner did not stay up'
        exit 1
    }

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
} finally {
    if (-not ((Test-PortListen 10808) -or (Test-PortListen 10809))) {
        if (Test-Path -LiteralPath $fullConfig) {
            Copy-Item -LiteralPath $fullConfig -Destination $configFile -Force
        }
        if (Test-Path -LiteralPath $fullMeta) {
            Copy-Item -LiteralPath $fullMeta -Destination $metaFile -Force
        }
        Start-XrayWait | Out-Null
        Write-ProbeLog 'xray was down after probe, started again'
    }
}
