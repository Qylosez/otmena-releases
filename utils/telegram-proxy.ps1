#Requires -Version 3.0
param(
    [string]$Mode = 'default',
    [switch]$Blind,
    [int]$BlindCount = 8
)

$Mts = ($Mode -eq 'mts' -or $env:TELEGRAM_MTS -eq '1')
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = Split-Path $PSScriptRoot -Parent
$cacheFile = Join-Path $PSScriptRoot 'telegram-proxy.cache.txt'
$cacheMtsFile = Join-Path $PSScriptRoot 'telegram-proxy-mts.cache.txt'

if ($Mts) { $cacheFile = $cacheMtsFile }

$listsRu = @(
    'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_ru.txt'
)
$listsAll = @(
    'https://raw.githubusercontent.com/kort0881/telegram-proxy-collector/main/proxy_all.txt',
    'https://raw.githubusercontent.com/Firmfox/Proxify/refs/heads/main/telegram_proxies/mtproto.txt'
)

function Write-Color($text, $color) {
    Write-Host $text -ForegroundColor $color
}

function Convert-ToTgProxyUri([string]$line) {
    $line = $line.Trim()
    if ($line -match '^tg://proxy\?') { return $line }
    if ($line -match '^tg://socks\?') { return $line }
    if ($line -match '^https://t\.me/proxy\?') { return ($line -replace '^https://t\.me/', 'tg://') }
    if ($line -match '^https://t\.me/socks\?') { return ($line -replace '^https://t\.me/', 'tg://') }
    return $null
}

function Resolve-ProxyHost([string]$server) {
    if ($server -match '^\d{1,3}(\.\d{1,3}){3}$') { return $server }
    try {
        $a = [System.Net.Dns]::GetHostAddresses($server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($a) { return $a.IPAddressToString }
    } catch {}
    return $server
}

function Test-ProxyTcp([string]$server, [int]$port, [int]$timeoutMs = 3500) {
    if ([string]::IsNullOrWhiteSpace($server)) { return $false }
    $targetHost = Resolve-ProxyHost $server
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($targetHost, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) { return $false }
        $client.EndConnect($iar) | Out-Null
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Parse-ProxyUri([string]$uri) {
    if ($uri -match '^tg://socks\?') {
        if ($uri -notmatch 'server=([^&]+).*?port=(\d+)') { return $null }
        return @{
            Kind   = 'socks'
            Server = $matches[1]
            Port   = [int]$matches[2]
            Uri    = $uri
        }
    }
    if ($uri -notmatch 'server=([^&]+).*?port=(\d+)') { return $null }
    $secret = ''
    if ($uri -match 'secret=([^&]+)') { $secret = $matches[1] }
    return @{
        Kind   = 'mtproto'
        Server = $matches[1]
        Port   = [int]$matches[2]
        Secret = $secret
        Uri    = $uri
    }
}

function Get-ProxyScore($p) {
    if (-not $p) { return 0 }
    $score = 0
    if ($p.Kind -eq 'socks') { return 1 }
    $sec = $p.Secret
    if ($sec -match '^ee') { $score += 12 }
    if ($sec -match '^dd') { $score += 4 }
    if ($sec -match '79616e646578|2e7275|766b2e|676f6f676c65') { $score += 6 }
    $srv = $p.Server.ToLower()
    if ($srv -match '\.ru$|yandex|vk\.com|mail\.ru|sber') { $score += 4 }
    if ($srv -match '^\d{1,3}(\.\d{1,3}){3}$') { $score += 1 }
    if ($p.Port -eq 443 -or $p.Port -eq 8443) { $score += 2 }
    return $score
}

function Invoke-ProxyLink([string]$uri) {
    Write-Color "  -> $uri" Green
    Start-Process $uri
}

function Show-MtsHelp {
    Write-Host ''
    Write-Color '=== MTS: WARP blocked - options ===' Cyan
    Write-Host '  A) FakeTLS MTProto (this script) - looks like HTTPS yandex/vk'
    Write-Host '  B) Tor + SOCKS5 in Telegram: 127.0.0.1 port 9150'
    Write-Host '  C) Oblivion VPN: winget install BepassOrg.OblivionDesktop'
    Write-Host '  D) Phone hotspot (another mobile operator)'
    Write-Host '  E) Own VPS + MTProto FakeTLS (telemt/mtg) - most stable'
    Write-Host ''
}

function Invoke-BlindProxies($proxyUris, [int]$count) {
    Write-Color "MTS: opening $count best FakeTLS proxies in Telegram (no TCP test)." Yellow
    Write-Color 'In TG pick proxy with status Connected. Disable others.' Yellow
    Write-Host ''
    $opened = 0
    foreach ($uri in $proxyUris) {
        if ($opened -ge $count) { break }
        Invoke-ProxyLink $uri
        $opened++
        Start-Sleep -Seconds 2
    }
    Write-Host ''
    Write-Color "Opened: $opened. Restart Telegram Desktop if stuck on Connecting." Green
}

function Fetch-ProxyLists([string[]]$urls) {
    $proxies = New-Object System.Collections.Generic.List[string]
    foreach ($url in $urls) {
        Write-Host "Loading: $url"
        try {
            $body = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20).Content
            foreach ($line in ($body -split "`n")) {
                $uri = Convert-ToTgProxyUri $line
                if ($uri -and -not $proxies.Contains($uri)) {
                    [void]$proxies.Add($uri)
                }
            }
        } catch {
            Write-Color "  failed: $($_.Exception.Message)" Yellow
        }
    }
    return $proxies
}

function Sort-ProxiesByScore($proxyUris) {
    $scored = @()
    foreach ($uri in $proxyUris) {
        $p = Parse-ProxyUri $uri
        if (-not $p) { continue }
        $scored += [PSCustomObject]@{ Uri = $uri; Score = (Get-ProxyScore $p); Parsed = $p }
    }
    return ($scored | Sort-Object -Property Score -Descending)
}

Write-Host ''
if ($Mts) {
    Write-Color '=== Telegram on MTS (no WARP) ===' Cyan
    Write-Host 'Keep zapret ALT11 for Discord/YouTube. Telegram needs proxy/VPN.'
    Show-MtsHelp
} else {
    Write-Color '=== Telegram: MTProto / SOCKS proxy ===' Cyan
    Write-Host 'Keep zapret ALT11 for Discord/YouTube. Telegram uses in-app proxy.'
}
Write-Host ''

if (-not $Blind -and (Test-Path $cacheFile)) {
    $cached = Get-Content $cacheFile -TotalCount 1 -ErrorAction SilentlyContinue
    if ($cached) {
        $p = Parse-ProxyUri $cached
        if ($p) {
            $ports = @($p.Port)
            if ($p.Kind -eq 'mtproto') { $ports += 443, 8443, 88 | Where-Object { $_ -ne $p.Port } }
            $ok = $false
            foreach ($port in $ports) {
                if (Test-ProxyTcp $p.Server $port) { $ok = $true; break }
            }
            if ($ok -or $Mts) {
                if ($ok) { Write-Color "Cache OK: $($p.Server):$($p.Port)" Green }
                else { Write-Color 'Cache (MTS): opening without TCP check' Yellow }
                Invoke-ProxyLink $cached
                Write-Host ''
                Write-Color 'TG: Settings -> Advanced -> connection type -> proxy' Yellow
                if (-not $Mts) { exit 0 }
            }
        }
    }
}

$urls = $listsRu + $listsAll
$proxies = Fetch-ProxyLists $urls

if ($proxies.Count -eq 0) {
    Write-Color 'Proxy list empty. Check internet/DNS.' Red
    if ($Mts) { Show-MtsHelp }
    exit 1
}

$sorted = Sort-ProxiesByScore $proxies
if ($Mts) {
    $sorted = $sorted | Where-Object { $_.Score -ge 6 -or $_.Parsed.Kind -eq 'socks' }
    if ($sorted.Count -eq 0) { $sorted = Sort-ProxiesByScore $proxies }
}

Write-Color "In list: $($proxies.Count), FakeTLS priority: $($sorted.Count)" Cyan

if ($Blind) {
    $uris = @($sorted | ForEach-Object { $_.Uri })
    Invoke-BlindProxies $uris $BlindCount
    exit 0
}

$maxTest = if ($Mts) { 150 } else { 80 }
$tested = 0
foreach ($item in $sorted) {
    if ($tested -ge $maxTest) { break }
    $p = $item.Parsed
    $uri = $item.Uri
    $tested++
    $ports = @($p.Port)
    if ($p.Kind -eq 'mtproto') {
        foreach ($extra in @(443, 8443, 88)) {
            if ($ports -notcontains $extra) { $ports += $extra }
        }
    }
    Write-Host "  [$tested] $($p.Server):$($p.Port) score=$($item.Score) ... " -NoNewline
    $alive = $false
    foreach ($port in $ports) {
        if (Test-ProxyTcp $p.Server $port) {
            $alive = $true
            break
        }
    }
    if ($alive) {
        Write-Color 'OK' Green
        $uri | Out-File -FilePath $cacheFile -Encoding UTF8 -Force
        Invoke-ProxyLink $uri
        Write-Host ''
        Write-Color 'Done. Restart Telegram if Connecting hangs.' Green
        Write-Color 'Settings -> Advanced -> proxy must be active.' Yellow
        exit 0
    }
    Write-Host 'no'
}

Write-Host ''
if ($Mts) {
    Write-Color 'TCP to proxies failed from PC - on MTS this is normal. Trying blind mode.' Yellow
    $top = @($sorted | Select-Object -First $BlindCount | ForEach-Object { $_.Uri })
    if ($top.Count -gt 0) {
        $top[0] | Out-File -FilePath $cacheFile -Encoding UTF8 -Force
        Invoke-BlindProxies $top $BlindCount
        Show-MtsHelp
        exit 0
    }
}

Write-Color 'No working proxy found by TCP test.' Red
if ($Mts) {
    Show-MtsHelp
} else {
    Write-Color 'On MTS run: TELEGRAM-MTS.bat' Yellow
    Write-Host '  WARP is often blocked on MTS. Use FakeTLS / Tor / Oblivion.'
}
exit 2
