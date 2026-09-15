#Requires -Version 3.0
# Keep Otmena services alive while desired-running.flag is present.
# If the Cursor tunnel dies, drop the Cursor proxy so the IDE does not
# infinite-reconnect against 127.0.0.1:10809.
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = Split-Path $PSScriptRoot -Parent
$flagFile = Join-Path $PSScriptRoot 'desired-running.flag'
$lockFile = Join-Path $PSScriptRoot 'watchdog.lock'
$logFile = Join-Path $PSScriptRoot 'watchdog.log'

function Write-WLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, $utf8)
    } catch {}
    if (-not $Quiet) { Write-Host $line }
}

function Test-AutostartEnabled {
    if (Get-ScheduledTask -TaskName 'Otmena-Start' -ErrorAction SilentlyContinue) { return $true }
    if (Get-ScheduledTask -TaskName 'Zapret-Start' -ErrorAction SilentlyContinue) { return $true }
    $startupDir = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
        if (Test-Path (Join-Path $startupDir $name)) { return $true }
    }
    return $false
}

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(800, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

# Single-instance lock (stale lock from a dead process is reused).
$myPid = $PID
if (Test-Path $lockFile) {
    $old = Get-Content $lockFile -ErrorAction SilentlyContinue
    if ($old -match '^\d+$') {
        $alive = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
        if ($alive) {
            Write-Output 'WATCHDOG=busy'
            exit 0
        }
    }
}
$myPid | Out-File -FilePath $lockFile -Encoding ASCII -Force

try {
    if (-not (Test-Path $flagFile)) {
        Write-Output 'WATCHDOG=idle'
        exit 0
    }

    $flagStale = $false
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $bootTime = $os.ConvertToDateTime($os.LastBootUpTime)
        $flagTime = (Get-Item $flagFile).LastWriteTime
        if ($flagTime -lt $bootTime -and -not (Test-AutostartEnabled)) {
            $flagStale = $true
        }
    } catch {}

    if ($flagStale) {
        Remove-Item $flagFile -Force -ErrorAction SilentlyContinue
        & (Join-Path $PSScriptRoot 'cursor-proxy.ps1') -Disable -Quiet | Out-Null
        Write-WLog 'stale desired-running.flag from previous boot (autostart off) - idle'
        Write-Output 'WATCHDOG=idle-stale'
        exit 0
    }

    $winws = [bool](Get-Process -Name winws -ErrorAction SilentlyContinue)
    if (-not $winws) {
        $bat = Join-Path $rootDir 'scripts\general (ALT11).bat'
        if (Test-Path $bat) {
            Write-WLog 'winws down - restart ALT11'
            Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -WorkingDirectory $rootDir -WindowStyle Hidden
            Start-Sleep -Seconds 4
        }
    }

    $needXray = -not ((Test-PortListen 10808) -and (Test-PortListen 10809))
    if ($needXray) {
        Write-WLog 'xray 10808/10809 down - restart tunnel'
        & (Join-Path $PSScriptRoot 'ensure-cursor-tunnel.ps1') -Quiet | Out-Null
        & (Join-Path $PSScriptRoot 'telegram-vless-daemon.ps1') -Quiet | Out-Null
        Start-Sleep -Seconds 2
    }

    if (Test-PortListen 10809) {
        & (Join-Path $PSScriptRoot 'cursor-proxy.ps1') -Quiet | Out-Null
        Write-Output 'WATCHDOG=ok CURSOR=1'
    } else {
        Write-WLog '10809 still down - disable Cursor proxy to stop reconnect loop'
        & (Join-Path $PSScriptRoot 'cursor-proxy.ps1') -Disable -Quiet | Out-Null
        Write-Output 'WATCHDOG=degraded CURSOR=0'
    }
    exit 0
} finally {
    if (Test-Path $lockFile) {
        $cur = Get-Content $lockFile -ErrorAction SilentlyContinue
        if ($cur -eq [string]$myPid) { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }
    }
}
