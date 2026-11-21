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

function Write-XrayStartLog([string]$msg) {
    $log = Join-Path $PSScriptRoot 'xray-start.log'
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch {}
}

function Test-XrayConfigFile {
    if (-not (Test-Path $xrayExe) -or -not (Test-Path $configFile)) { return $false }
    $code = -1
    $text = ''
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $xrayExe
        $psi.Arguments = "run -test -c `"$configFile`""
        $psi.WorkingDirectory = $vlessDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(8000)) {
            try { $p.Kill() } catch {}
            $code = -1
        } else {
            $code = $p.ExitCode
        }
        $text = (([string]$outTask.Result) + "`n" + ([string]$errTask.Result)).Trim()
    } catch {
        $code = Start-OtmenaNativeProcess -FilePath $xrayExe -Arguments "run -test -c `"$configFile`"" -WorkingDirectory $vlessDir -Wait -WaitMs 8000
        $text = [string]$_.Exception.Message
    }
    $log = Join-Path $PSScriptRoot 'xray-test.log'
    try { Set-Content -LiteralPath $log -Value ("exit={0}`r`n{1}" -f $code, $text) -Encoding UTF8 } catch {}
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

    $syncOut = & (Join-Path $PSScriptRoot 'sync-vless-config.ps1') -Quiet | Out-String
    if ($syncOut -match 'VLESS_SYNC=cache') {
        if (Wait-OtmenaNetwork -Seconds 15) {
            & (Join-Path $PSScriptRoot 'sync-vless-config.ps1') -Quiet | Out-Null
        }
    }
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
$socksUp = [int](Test-PortListen $socksPort)
$httpUp = [int](Test-PortListen $httpPort)
$cursorSocksUp = [int](Test-PortListen 10810)
Write-Output ("XRAY_STATUS={0}" -f $tg)
Write-Output ("XRAY_SOCKS={0}" -f $socksUp)
Write-Output ("XRAY_HTTP={0}" -f $httpUp)
Write-XrayStartLog ("status={0} socks10808={1} http10809={2} socks10810={3}" -f $tg, $socksUp, $httpUp, $cursorSocksUp)

if (-not $Quiet) {
    Write-Host "telegram socks: $tg (127.0.0.1:$socksPort)"
    Write-Host "system proxy: OFF (games not affected)"
}
