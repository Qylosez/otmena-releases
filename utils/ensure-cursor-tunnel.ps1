#Requires -Version 3.0
# Make sure telegram-vless/config.json has HTTP 10809 + SOCKS 10810 for Cursor/AI.
# Existing installs keep an old config.json across updates (preserve list), so
# launcher used to skip Cursor Europe because port 10809 never existed.
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = Split-Path $PSScriptRoot -Parent
$configFile = Join-Path $rootDir 'telegram-vless\config.json'

function Write-Note($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

function As-Array($value) {
    if ($null -eq $value) { return @() }
    if ($value -is [System.Array]) { return @($value) }
    return @($value)
}

function Get-InboundPorts($cfg) {
    $ports = New-Object System.Collections.Generic.HashSet[int]
    foreach ($ib in (As-Array $cfg.inbounds)) {
        try { [void]$ports.Add([int]$ib.port) } catch {}
    }
    return $ports
}

function Get-VlessSettings($cfg) {
    foreach ($ob in (As-Array $cfg.outbounds)) {
        if ([string]$ob.protocol -ne 'vless') { continue }
        $vnext = (As-Array $ob.settings.vnext | Select-Object -First 1)
        if (-not $vnext) { continue }
        $user = (As-Array $vnext.users | Select-Object -First 1)
        $reality = $ob.streamSettings.realitySettings
        if (-not $user -or -not $reality) { continue }
        return @{
            Address     = [string]$vnext.address
            Port        = [int]$vnext.port
            Id          = [string]$user.id
            ServerName  = [string]$reality.serverName
            Fingerprint = [string]$reality.fingerprint
            PublicKey   = [string]$reality.publicKey
            ShortId     = [string]$reality.shortId
        }
    }
    return $null
}

function Write-TunnelConfig($vless) {
    $fp = $vless.Fingerprint
    if (-not $fp) { $fp = 'qq' }
    $sid = $vless.ShortId
    if ($null -eq $sid) { $sid = '' }

    $obj = @{
        log = @{ loglevel = 'warning' }
        inbounds = @(
            @{
                tag = 'socks-tg'
                listen = '127.0.0.1'
                port = 10808
                protocol = 'socks'
                settings = @{ auth = 'noauth'; udp = $true }
                sniffing = @{ enabled = $true; destOverride = @('http', 'tls', 'quic') }
            },
            @{
                tag = 'http-cursor'
                listen = '127.0.0.1'
                port = 10809
                protocol = 'http'
                settings = @{ allowTransparent = $false }
                sniffing = @{ enabled = $true; destOverride = @('http', 'tls', 'quic') }
            },
            @{
                tag = 'socks-cursor'
                listen = '127.0.0.1'
                port = 10810
                protocol = 'socks'
                settings = @{ auth = 'noauth'; udp = $true }
                sniffing = @{ enabled = $true; destOverride = @('http', 'tls', 'quic') }
            }
        )
        outbounds = @(
            @{
                tag = 'proxy'
                protocol = 'vless'
                settings = @{
                    vnext = @(
                        @{
                            address = $vless.Address
                            port = $vless.Port
                            users = @(
                                @{
                                    id = $vless.Id
                                    encryption = 'none'
                                }
                            )
                        }
                    )
                }
                streamSettings = @{
                    network = 'tcp'
                    security = 'reality'
                    realitySettings = @{
                        serverName = $vless.ServerName
                        fingerprint = $fp
                        publicKey = $vless.PublicKey
                        shortId = $sid
                    }
                }
            },
            @{ tag = 'direct'; protocol = 'freedom' },
            @{ tag = 'block'; protocol = 'blackhole' }
        )
        routing = @{
            domainStrategy = 'IPIfNonMatch'
            rules = @(
                @{
                    type = 'field'
                    ip = @('127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16')
                    outboundTag = 'direct'
                },
                @{
                    type = 'field'
                    inboundTag = @('socks-tg', 'http-cursor', 'socks-cursor')
                    outboundTag = 'proxy'
                }
            )
        }
        remarks = 'Otmena | Poland Reality | TG SOCKS 10808 + Cursor HTTP 10809 / SOCKS 10810'
    }

    $json = $obj | ConvertTo-Json -Depth 12
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $backup = "$configFile.otmena.bak"
    if ((Test-Path $configFile) -and -not (Test-Path $backup)) {
        Copy-Item $configFile $backup -Force
    }
    [System.IO.File]::WriteAllText($configFile, $json, $utf8)
}

if (-not (Test-Path $configFile)) {
    Write-Note 'config.json ne najden - Cursor Europe ne podnjat.' Yellow
    Write-Output 'CURSOR_CONFIG=missing'
    exit 1
}

$raw = Get-Content $configFile -Raw -ErrorAction SilentlyContinue
try {
    $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Note 'config.json slomann - ne perepisyvaju.' Red
    Write-Output 'CURSOR_CONFIG=invalid'
    exit 1
}

$ports = Get-InboundPorts $cfg
$hasHttp = $ports.Contains([int]10809)
$hasSocks = $ports.Contains([int]10810)
$hasTg = $ports.Contains([int]10808)

if ($hasHttp -and $hasSocks -and $hasTg) {
    Write-Note 'xray inbounds 10808/10809/10810 uzhe est.' DarkGray
    Write-Output 'CURSOR_CONFIG=ok'
    exit 0
}

$vless = Get-VlessSettings $cfg
if (-not $vless -or -not $vless.Address -or -not $vless.Id -or -not $vless.PublicKey) {
    Write-Note 'VLESS kljuch v config.json ne najden - ne trogaju fajl.' Red
    Write-Output 'CURSOR_CONFIG=no-vless'
    exit 1
}

Write-Note 'Dobavljaju Cursor inbounds 10809/10810 v config.json (staryj fajl sohranjon kak .otmena.bak).' Cyan
Write-TunnelConfig $vless
Write-Output 'CURSOR_CONFIG=updated'
exit 0
