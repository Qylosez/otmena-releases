#Requires -Version 3.0
# Background watchdog: never leave Cursor on a dead local proxy.

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')

$logFile = Join-Path $PSScriptRoot 'cursor-watch.log'
$intervalSec = 20
$deadStreak = 0
$deadLimit = 2

function Write-WatchLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, $utf8)
    } catch {}
}

Write-WatchLog 'watch start'

while ($true) {
    $state = Get-CursorProxyState
    $hasProxy = Test-CursorProxyEnabled
    $ep = Get-CursorTunnelEndpoint
    $settingsProxy = Get-CursorSettingsProxyUrl
    $expected = Get-CursorProxyUrl

    if ($hasProxy -and $expected -and $settingsProxy -and ($settingsProxy -ne $expected)) {
        Write-WatchLog ("settings mismatch -> repair ($settingsProxy -> $expected)")
        Enable-CursorTunnelProxy -Quiet | Out-Null
        $deadStreak = 0
    }
    elseif ($hasProxy -and -not $ep) {
        $deadStreak++
        if ($deadStreak -ge $deadLimit) {
            Write-WatchLog 'proxy set but tunnel dead -> disable'
            Disable-CursorTunnelProxy -Quiet
            $deadStreak = 0
        }
    }
    elseif ($state.enabledByOtmena -and $ep -and -not $hasProxy) {
        Write-WatchLog ("tunnel live ($($ep.Label)) -> restore proxy")
        Enable-CursorTunnelProxy -Quiet | Out-Null
        $deadStreak = 0
    }
    elseif ($ep) {
        Set-CursorProxyState -enabledByOtmena:$state.enabledByOtmena -Mode $ep.Mode -Port $ep.Port -Label $ep.Label -MarkOk
        $deadStreak = 0
    }
    else {
        $deadStreak = 0
    }

    Start-Sleep -Seconds $intervalSec
}
