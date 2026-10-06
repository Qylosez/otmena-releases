#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')
$rootDir = Split-Path $PSScriptRoot -Parent
$vlessDir = Join-Path $rootDir 'telegram-vless'
$configFile = Join-Path $vlessDir 'config.json'
$configBak = Join-Path $vlessDir 'config.json.bak'
$xrayExe = Join-Path $vlessDir 'bin\xray.exe'
$pidFile = Join-Path $vlessDir 'xray.pid'
$socksPort = 10808
$httpPort = 10809

function Maybe-DisableSystemProxy {
    $stateFile = Join-Path $PSScriptRoot 'cursor-proxy.state.json'
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($state.enabledByOtmena) { return }
        } catch {}
    }
    & (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')
}

function Restore-CursorProxyAfterXray {
    $stateFile = Join-Path $PSScriptRoot 'cursor-proxy.state.json'
    if (-not (Test-Path $stateFile)) { return }
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($state.enabledByOtmena) {
            . (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')
            Enable-CursorTunnelProxy -Quiet | Out-Null
        }
    } catch {}
}

Maybe-DisableSystemProxy

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(400, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Test-CorePorts {
    return (Test-PortListen $socksPort) -and (Test-PortListen $httpPort)
}

function Stop-StaleXray {
    if (Test-Path $pidFile) {
        $old = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($old -match '^\d+$') {
            Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue
        }
    }
    Get-Process xray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
}

function Test-XrayConfigFile {
    if (-not (Test-Path $xrayExe) -or -not (Test-Path $configFile)) { return $false }
    $code = Start-OtmenaNativeProcess -FilePath $xrayExe -Arguments "run -test -c `"$configFile`"" -WorkingDirectory $vlessDir -Wait -WaitMs 8000
    return ($code -eq 0)
}

function Start-XrayProcess {
    $proc = Start-OtmenaNativeProcess -FilePath $xrayExe -Arguments "run -config `"$configFile`"" -WorkingDirectory $vlessDir
    if ($proc -and $proc.Id) {
        $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -Force
    }
    return $proc
}

function Wait-XrayReady($proc, [int]$tries = 20) {
    for ($i = 0; $i -lt $tries; $i++) {
        if ($proc -and $proc.HasExited) { return $false }
        if (Test-CorePorts) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return (Test-CorePorts)
}

function Start-XrayQuiet {
    if (Test-Path $configFile) {
        Copy-Item -Path $configFile -Destination $configBak -Force -ErrorAction SilentlyContinue
    }

    & (Join-Path $PSScriptRoot 'sync-vless-config.ps1') -Quiet | Out-Null
    if (-not (Test-Path $xrayExe)) {
        & (Join-Path $PSScriptRoot 'ensure-xray.ps1') -Quiet | Out-Null
        if (-not (Test-Path $xrayExe)) { return 'no-xray' }
    }
    Ensure-OtmenaNativeDeps $rootDir | Out-Null

    if (-not (Test-XrayConfigFile)) {
        & (Join-Path $PSScriptRoot 'sync-vless-config.ps1') -Quiet -Offline -Single | Out-Null
    }

    Stop-StaleXray
    $proc = Start-XrayProcess
    if (Wait-XrayReady $proc) { return 'started' }

    Stop-StaleXray
    & (Join-Path $PSScriptRoot 'sync-vless-config.ps1') -Quiet -Offline -Single | Out-Null
    $proc = Start-XrayProcess
    if (Wait-XrayReady $proc) { return 'started-single' }

    if (Test-Path $configBak) {
        Copy-Item -Path $configBak -Destination $configFile -Force -ErrorAction SilentlyContinue
        Stop-StaleXray
        $proc = Start-XrayProcess
        if (Wait-XrayReady $proc) { return 'started-backup' }
    }
    return 'failed'
}

$tg = Start-XrayQuiet
Restore-CursorProxyAfterXray
Write-Output ("XRAY_STATUS={0}" -f $tg)
Write-Output ("XRAY_SOCKS={0}" -f [int](Test-PortListen $socksPort))
Write-Output ("XRAY_HTTP={0}" -f [int](Test-PortListen $httpPort))

if (-not $Quiet) {
    Write-Host "telegram socks: $tg (127.0.0.1:$socksPort)"
    Write-Host "system proxy: OFF (games not affected)"
}
