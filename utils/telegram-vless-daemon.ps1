#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = Split-Path $PSScriptRoot -Parent
$vlessDir = Join-Path $rootDir 'telegram-vless'
$configFile = Join-Path $vlessDir 'config.json'
$xrayExe = Join-Path $vlessDir 'bin\xray.exe'
$pidFile = Join-Path $vlessDir 'xray.pid'
$socksPort = 10808

& (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(1200, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Start-XrayQuiet {
    if (Test-PortListen $socksPort) { return 'running' }
    if (-not (Test-Path $xrayExe)) {
        & (Join-Path $PSScriptRoot 'ensure-xray.ps1') -Quiet | Out-Null
        if (-not (Test-Path $xrayExe)) { return 'no-xray' }
    }

    if (Test-Path $pidFile) {
        $old = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($old -match '^\d+$') {
            $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
            if ($p) { return 'running' }
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $xrayExe
    $psi.Arguments = "run -config `"$configFile`""
    $psi.WorkingDirectory = $vlessDir
    $psi.WindowStyle = 'Hidden'
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -Force

    for ($i = 0; $i -lt 12; $i++) {
        if (Test-PortListen $socksPort) { return 'started' }
        Start-Sleep -Seconds 1
    }
    return 'failed'
}

$tg = Start-XrayQuiet

if (-not $Quiet) {
    Write-Host "telegram socks: $tg (127.0.0.1:$socksPort)"
    Write-Host "system proxy: OFF (games not affected)"
}
