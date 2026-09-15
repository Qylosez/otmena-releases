#Requires -Version 3.0
# Shared Cursor tunnel helpers for Otmena.

$ErrorActionPreference = 'SilentlyContinue'

$script:TelegramSocksPort = 10808
$script:CursorSocksPort = 10810
$script:CursorHttpPort = 10809

function Test-WorkModeEnabled {
    return Test-Path (Join-Path $PSScriptRoot 'work_mode.enabled')
}

function Test-TgPortLive {
    return Test-PortListen $script:TelegramSocksPort
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

function Test-XrayRunning {
    return [bool](Get-Process -Name xray -ErrorAction SilentlyContinue)
}

function Get-CursorSettingsPaths {
    return @(
        (Join-Path $env:APPDATA 'Cursor\User\settings.json'),
        (Join-Path $env:APPDATA 'Cursor Nightly\User\settings.json')
    )
}

function ConvertFrom-Jsonc([string]$raw) {
    if (-not $raw -or -not $raw.Trim()) { return $null }
    $noBlock = [System.Text.RegularExpressions.Regex]::Replace($raw, '/\*.*?\*/', '', 'Singleline')
    $noLine = [System.Text.RegularExpressions.Regex]::Replace($noBlock, '(^|\s)//.*$', '$1', 'Multiline')
    try { return $noLine | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Get-CursorSettingsProxyUrl {
    foreach ($path in (Get-CursorSettingsPaths)) {
        if (-not (Test-Path $path)) { continue }
        $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
        $obj = ConvertFrom-Jsonc $raw
        if ($obj -and $obj.'http.proxy') { return [string]$obj.'http.proxy' }
    }
    return $null
}

function Test-CursorProxyEnabled {
    foreach ($path in (Get-CursorSettingsPaths)) {
        if (-not (Test-Path $path)) { continue }
        $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        if ($raw -match '127\.0\.0\.1:108(08|09|10)') { return $true }
        if ($raw -match '"http\.proxy"\s*:') { return $true }
    }
    return $false
}

function Invoke-CurlCode {
    param(
        [string]$Url,
        [string[]]$ProxyArg,
        [int]$TimeoutSec = 8
    )
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return $null }
    try {
        return (& curl.exe -s -o NUL -w '%{http_code}' @ProxyArg $Url --connect-timeout $TimeoutSec --max-time ($TimeoutSec + 3) 2>$null)
    } catch {
        return $null
    }
}

function Test-EndpointLive {
    param(
        [ValidateSet('socks', 'http')]
        [string]$Mode,
        [int]$Port
    )

    if (-not (Test-PortListen $Port)) { return $false }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        return ($Port -eq $script:TelegramSocksPort -and (Test-XrayRunning))
    }

    $proxyArg = if ($Mode -eq 'socks') {
        @('--socks5-hostname', "127.0.0.1:$Port")
    } else {
        @('-x', "http://127.0.0.1:$Port")
    }

    foreach ($url in @('https://api2.cursor.sh', 'https://www.cursor.com', 'https://www.gstatic.com/generate_204')) {
        $code = Invoke-CurlCode -Url $url -ProxyArg $proxyArg -TimeoutSec 8
        if ($code -match '^(200|204|301|302|307|308)$') { return $true }
    }
    return $false
}

function Get-CursorTunnelEndpoint {
    $metaFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'telegram-vless\subscription.meta.json'
    if (Test-Path $metaFile) {
        try {
            $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
            if ($meta.cursorMode -eq 'http' -and (Test-PortListen $script:CursorHttpPort)) {
                if (Test-EndpointLive -Mode http -Port $script:CursorHttpPort) {
                    return [PSCustomObject]@{ Mode = 'http'; Port = $script:CursorHttpPort; Label = 'meta-http' }
                }
            }
        } catch {}
    }

    if (Test-WorkModeEnabled) {
        $workCandidates = @(
            [PSCustomObject]@{ Mode = 'http';  Port = $script:CursorHttpPort;  Label = 'cursor-http' },
            [PSCustomObject]@{ Mode = 'socks'; Port = $script:TelegramSocksPort; Label = 'tg-socks' },
            [PSCustomObject]@{ Mode = 'socks'; Port = $script:CursorSocksPort; Label = 'cursor-socks' }
        )
        foreach ($c in $workCandidates) {
            if (Test-EndpointLive -Mode $c.Mode -Port $c.Port) { return $c }
        }
        return $null
    }

    $candidates = @(
        [PSCustomObject]@{ Mode = 'socks'; Port = $script:TelegramSocksPort; Label = 'tg-socks' },
        [PSCustomObject]@{ Mode = 'http';  Port = $script:CursorHttpPort;  Label = 'cursor-http' },
        [PSCustomObject]@{ Mode = 'socks'; Port = $script:CursorSocksPort; Label = 'cursor-socks' }
    )

    foreach ($c in $candidates) {
        if (Test-EndpointLive -Mode $c.Mode -Port $c.Port) { return $c }
    }

    return $null
}

function Get-CursorTunnelMode {
    $ep = Get-CursorTunnelEndpoint
    if (-not $ep) { return 'none' }
    if ($ep.Port -eq $script:TelegramSocksPort) { return 'socks-tg' }
    if ($ep.Mode -eq 'http') { return 'http' }
    return 'socks'
}

function Get-CursorProxyStateFile {
    return Join-Path $PSScriptRoot 'cursor-proxy.state.json'
}

function Get-CursorProxyState {
    $file = Get-CursorProxyStateFile
    if (-not (Test-Path $file)) {
        return [PSCustomObject]@{
            enabledByOtmena = $false
            mode            = 'none'
            port            = 0
            label           = 'none'
            lastOk          = $null
        }
    }
    try {
        return Get-Content $file -Raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{
            enabledByOtmena = $false
            mode            = 'none'
            port            = 0
            label           = 'none'
            lastOk          = $null
        }
    }
}

function Set-CursorProxyState {
    param(
        [bool]$enabledByOtmena,
        [string]$Mode = 'none',
        [int]$Port = 0,
        [string]$Label = 'none',
        [switch]$MarkOk
    )
    $prev = Get-CursorProxyState
    $state = [ordered]@{
        enabledByOtmena = $enabledByOtmena
        mode            = $Mode
        port            = $Port
        label           = $Label
        lastOk          = if ($MarkOk) { (Get-Date).ToString('s') } else { $prev.lastOk }
    }
    ($state | ConvertTo-Json -Compress) | Out-File -FilePath (Get-CursorProxyStateFile) -Encoding ASCII -Force
}

function Clear-StaleCursorProxy {
    param([switch]$Quiet)

    $ep = Get-CursorTunnelEndpoint
    if ($ep) {
        Set-CursorProxyState -enabledByOtmena:(Get-CursorProxyState).enabledByOtmena -Mode $ep.Mode -Port $ep.Port -Label $ep.Label -MarkOk
        return $ep.Label
    }

    if (Test-CursorProxyEnabled) {
        Disable-CursorTunnelProxy -Quiet:$Quiet
        if (-not $Quiet) {
            Write-Host 'Cursor: ubral zaliпshij proksi (tunnel ne otvechaet).' -ForegroundColor Yellow
        }
        return 'cleared'
    }

    return 'idle'
}

function Enable-CursorTunnelProxy {
    param([switch]$Quiet)

    $ep = Get-CursorTunnelEndpoint
    if (-not $ep) {
        Clear-StaleCursorProxy -Quiet:$Quiet | Out-Null
        return $false
    }

    $proxyScript = Join-Path $PSScriptRoot 'cursor-proxy.ps1'
    & $proxyScript -Mode $ep.Mode -Port $ep.Port -Label $ep.Label -Quiet:$Quiet 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }

    if (Test-WorkModeEnabled) {
        . (Join-Path $PSScriptRoot 'cursor-system-proxy.ps1')
        $sysPort = if ($ep.Mode -eq 'http') { $ep.Port } else { $script:CursorHttpPort }
        if (Test-PortListen $sysPort) {
            Enable-CursorSystemProxy -Port $sysPort
        }
    }

    Set-CursorProxyState -enabledByOtmena:$true -Mode $ep.Mode -Port $ep.Port -Label $ep.Label -MarkOk
    Start-CursorWatch | Out-Null
    return $true
}

function Get-CursorProxyUrl {
    $ep = Get-CursorTunnelEndpoint
    if (-not $ep) { return $null }
    if ($ep.Mode -eq 'socks') { return "socks5://127.0.0.1:$($ep.Port)" }
    return "http://127.0.0.1:$($ep.Port)"
}

function Disable-CursorTunnelProxy {
    param([switch]$Quiet)

    & (Join-Path $PSScriptRoot 'cursor-proxy.ps1') -Disable -Quiet:$Quiet 2>$null | Out-Null
    if (Test-WorkModeEnabled) {
        . (Join-Path $PSScriptRoot 'cursor-system-proxy.ps1')
        Disable-CursorSystemProxy
    }
    & (Join-Path $PSScriptRoot 'disable-system-proxy.ps1') 2>$null | Out-Null
    Set-CursorProxyState -enabledByOtmena:$false -Mode 'none' -Port 0 -Label 'none'
}

function Start-CursorWatch {
    $watchScript = Join-Path $PSScriptRoot 'cursor-watch.ps1'
    $pidFile = Join-Path $PSScriptRoot 'cursor-watch.pid'
    if (-not (Test-Path $watchScript)) { return $false }

    if (Test-Path $pidFile) {
        $old = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($old -match '^\d+$') {
            $p = Get-Process -Id ([int]$old) -ErrorAction SilentlyContinue
            if ($p) { return $true }
        }
    }

    $proc = Start-Process -FilePath (Get-Command powershell.exe).Source `
        -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchScript`"" `
        -WindowStyle Hidden -PassThru
    if ($proc -and $proc.Id) {
        $proc.Id | Out-File -FilePath $pidFile -Encoding ASCII -Force
        return $true
    }
    return $false
}

function Stop-CursorWatch {
    $pidFile = Join-Path $PSScriptRoot 'cursor-watch.pid'
    if (-not (Test-Path $pidFile)) { return }
    $old = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($old -match '^\d+$') {
        Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Get-CursorTunnelDiagnostics {
    $ep = Get-CursorTunnelEndpoint
    return [ordered]@{
        TG_PORT        = $script:TelegramSocksPort
        SOCKS_PORT     = $script:CursorSocksPort
        HTTP_PORT      = $script:CursorHttpPort
        TG_LISTEN      = [int](Test-PortListen $script:TelegramSocksPort)
        SOCKS_LISTEN   = [int](Test-PortListen $script:CursorSocksPort)
        HTTP_LISTEN    = [int](Test-PortListen $script:CursorHttpPort)
        XRAY           = [int](Test-XrayRunning)
        CURL           = [int]([bool](Get-Command curl.exe -ErrorAction SilentlyContinue))
        SOCKS_LIVE     = [int](Test-EndpointLive -Mode socks -Port $script:TelegramSocksPort)
        HTTP_LIVE      = [int](Test-EndpointLive -Mode http -Port $script:CursorHttpPort)
        TUNNEL_UP      = [int]([bool]$ep)
        ENDPOINT       = if ($ep) { "$($ep.Label):$($ep.Port)" } else { 'none' }
        MODE           = (Get-CursorTunnelMode)
        PROXY_SET      = [int](Test-CursorProxyEnabled)
        PROXY_URL      = (Get-CursorProxyUrl)
        SETTINGS_PROXY = (Get-CursorSettingsProxyUrl)
        STATE          = ((Get-CursorProxyState | ConvertTo-Json -Compress))
    }
}

function Test-CursorTunnelLive {
    return [bool](Get-CursorTunnelEndpoint)
}
