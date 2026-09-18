#Requires -Version 3.0
<#
  Fetches the vpn.dance subscription (or uses a local cache) and writes
  telegram-vless\config.json for xray: SOCKS 10808 + HTTP 10809 + SOCKS 10810,
  with Reality TCP / gRPC / WS outbounds and leastPing balancer.
#>
param(
    [switch]$Quiet,
    [switch]$Offline,
    [switch]$Single,
    [int]$ProfileIndex = -1
)

$ErrorActionPreference = 'SilentlyContinue'
$utilsDir = $PSScriptRoot
$rootDir = Split-Path $utilsDir -Parent
$vlessDir = Join-Path $rootDir 'telegram-vless'
$configFile = Join-Path $vlessDir 'config.json'
$subFile = Join-Path $vlessDir 'subscription.json'
$cacheFile = Join-Path $vlessDir 'subscription.cache.txt'
$metaFile = Join-Path $vlessDir 'subscription.meta.json'

function Say($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

function Get-QueryMap([string]$query) {
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($query)) { return $map }
    foreach ($pair in $query.Split('&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $eq = $pair.IndexOf('=')
        if ($eq -lt 0) {
            $map[$pair] = ''
            continue
        }
        $k = [Uri]::UnescapeDataString($pair.Substring(0, $eq))
        $v = [Uri]::UnescapeDataString($pair.Substring($eq + 1))
        $map[$k] = $v
    }
    return $map
}

function ConvertFrom-VlessUri([string]$raw) {
    $line = $raw.Trim()
    if ($line -notmatch '^vless://') { return $null }
    $noScheme = $line.Substring(8)
    $hash = $noScheme.IndexOf('#')
    $remark = ''
    if ($hash -ge 0) {
        $remark = [Uri]::UnescapeDataString($noScheme.Substring($hash + 1))
        $noScheme = $noScheme.Substring(0, $hash)
    }
    $q = $noScheme.IndexOf('?')
    $query = ''
    $main = $noScheme
    if ($q -ge 0) {
        $query = $noScheme.Substring($q + 1)
        $main = $noScheme.Substring(0, $q)
    }
    $at = $main.LastIndexOf('@')
    if ($at -lt 0) { return $null }
    $uuid = $main.Substring(0, $at)
    $hostPort = $main.Substring($at + 1)
    $colon = $hostPort.LastIndexOf(':')
    if ($colon -lt 0) { return $null }
    $address = $hostPort.Substring(0, $colon).Trim('[', ']')
    $port = 0
    if (-not [int]::TryParse($hostPort.Substring($colon + 1), [ref]$port)) { return $null }
    $p = Get-QueryMap $query
    $type = if ($p['type']) { $p['type'] } else { 'tcp' }
    $security = if ($p['security']) { $p['security'] } else { 'none' }
    return [PSCustomObject]@{
        Uuid      = $uuid
        Address   = $address
        Port      = $port
        Type      = $type.ToLowerInvariant()
        Security  = $security.ToLowerInvariant()
        Sni       = $p['sni']
        Fp        = if ($p['fp']) { $p['fp'] } else { 'chrome' }
        Pbk       = $p['pbk']
        Sid       = if ($null -ne $p['sid']) { $p['sid'] } else { '' }
        Path      = if ($p['path']) { $p['path'] } else { '/' }
        Host      = $p['host']
        Service   = if ($p['serviceName']) { $p['serviceName'] } else { 'grpcservice' }
        Flow      = $p['flow']
        Remark    = $remark
    }
}

function Get-SubscriptionText {
    $url = $null
    if (Test-Path $subFile) {
        try {
            $cfg = Get-Content $subFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.url) { $url = [string]$cfg.url }
        } catch {}
    }
    if (-not $Offline -and $url) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
            $body = [string]$resp.Content
            if ($body) {
                $body.Trim() | Out-File -FilePath $cacheFile -Encoding ASCII -Force
                return $body
            }
        } catch {
            Say 'vpn.dance: ne udalos obnovit podpisku, beru kesh.' Yellow
        }
    }
    if (Test-Path $cacheFile) {
        return Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue
    }
    return $null
}

function ConvertFrom-SubscriptionBody([string]$body) {
    if ([string]::IsNullOrWhiteSpace($body)) { return @() }
    $text = $body.Trim()
    if ($text -notmatch '^vless://') {
        try {
            $pad = $text.Length % 4
            if ($pad) { $text += ('=' * (4 - $pad)) }
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($text))
            if ($decoded) { $text = $decoded }
        } catch {}
    }
    $links = @()
    foreach ($line in ($text -split "[\r\n]+")) {
        $parsed = ConvertFrom-VlessUri $line
        if ($parsed) { $links += $parsed }
    }
    return $links
}

function Get-JsonString([string]$s) {
    if ($null -eq $s) { $s = '' }
    return ($s | ConvertTo-Json -Compress)
}

function New-OutboundJson($link, [string]$tag) {
    $idJson = Get-JsonString $link.Uuid
    $addrJson = Get-JsonString $link.Address
    $enc = '"encryption": "none"'
    if ($link.Flow) { $enc += ', "flow": ' + (Get-JsonString $link.Flow) }
    $user = "{ `"id`": $idJson, $enc }"
    $vnext = "{ `"address`": $addrJson, `"port`": $($link.Port), `"users`": [ $user ] }"
    $network = $link.Type
    $security = $link.Security
    if ($security -eq 'tls' -or $security -eq 'xtls') { $security = 'tls' }
    $streamParts = New-Object System.Collections.Generic.List[string]
    $streamParts.Add(('      "network": {0}' -f (Get-JsonString $network)))
    $streamParts.Add(('      "security": {0}' -f (Get-JsonString $security)))
    if ($security -eq 'reality') {
        $sni = if ($link.Sni) { $link.Sni } else { $link.Address }
        $streamParts.Add(@"
      "realitySettings": {
        "serverName": $(Get-JsonString $sni),
        "fingerprint": $(Get-JsonString $link.Fp),
        "publicKey": $(Get-JsonString $link.Pbk),
        "shortId": $(Get-JsonString $link.Sid)
      }
"@)
    } elseif ($security -eq 'tls') {
        $sni = if ($link.Sni) { $link.Sni } else { $link.Address }
        $streamParts.Add(@"
      "tlsSettings": {
        "serverName": $(Get-JsonString $sni),
        "allowInsecure": false,
        "fingerprint": $(Get-JsonString $link.Fp)
      }
"@)
    }
    if ($network -eq 'grpc') {
        $streamParts.Add(@"
      "grpcSettings": {
        "serviceName": $(Get-JsonString $link.Service),
        "multiMode": false
      }
"@)
    } elseif ($network -eq 'ws') {
        $hostLine = ''
        if ($link.Host) { $hostLine = ('        "host": {0},' -f (Get-JsonString $link.Host)) + [Environment]::NewLine }
        $streamParts.Add(@"
      "wsSettings": {
$hostLine        "path": $(Get-JsonString $link.Path)
      }
"@)
    }
    $stream = ($streamParts -join ",`n")
    return @"
    {
      "tag": "$tag",
      "protocol": "vless",
      "settings": {
        "vnext": [ $vnext ]
      },
      "streamSettings": {
$stream
      }
    }
"@
}

function Get-PreferOrder {
    $order = @('tcp', 'grpc', 'ws')
    if (Test-Path $subFile) {
        try {
            $cfg = Get-Content $subFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.prefer) { $order = @($cfg.prefer) }
        } catch {}
    }
    return $order
}

function Get-ProbeUrl {
    $url = 'https://www.gstatic.com/generate_204'
    if (Test-Path $subFile) {
        try {
            $cfg = Get-Content $subFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.probeUrl) { $url = [string]$cfg.probeUrl }
        } catch {}
    }
    return $url
}

function Get-TagForLink($link, $used) {
    $base = switch ($link.Type) {
        'grpc' { 'proxy-grpc' }
        'ws' { 'proxy-ws' }
        default { 'proxy-tcp' }
    }
    $tag = $base
    $n = 2
    while ($used.Contains($tag)) {
        $tag = "$base-$n"
        $n++
    }
    $used.Add($tag) | Out-Null
    return $tag
}

$rawSub = Get-SubscriptionText
$links = @(ConvertFrom-SubscriptionBody $rawSub)
if ($links.Count -eq 0) {
    Say 'VLESS: net profilej v podpiske, ostavlyayu tekushij config.json' Yellow
    Write-Output 'VLESS_SYNC=cache-miss'
    exit 1
}

$prefer = Get-PreferOrder
$sorted = @()
foreach ($kind in $prefer) {
    $sorted += @($links | Where-Object { $_.Type -eq $kind })
}
$sorted += @($links | Where-Object { $prefer -notcontains $_.Type })
# unique by type+port+address
$seen = @{}
$unique = @()
$supported = @('tcp', 'grpc', 'ws')
foreach ($l in $sorted) {
    if ($supported -notcontains $l.Type) { continue }
    $k = '{0}|{1}|{2}' -f $l.Address, $l.Port, $l.Type
    if ($seen.ContainsKey($k)) { continue }
    $seen[$k] = $true
    $unique += $l
}

if ($ProfileIndex -ge 0 -and $ProfileIndex -lt $unique.Count) {
    $unique = @($unique[$ProfileIndex])
    $Single = $true
}

$usedTags = New-Object System.Collections.Generic.List[string]
$outboundJson = @()
$selectorTags = @()
foreach ($l in $unique) {
    $tag = Get-TagForLink $l $usedTags
    $outboundJson += (New-OutboundJson $l $tag)
    $selectorTags += $tag
}
if ($Single -and $selectorTags.Count -gt 1) {
    $outboundJson = @($outboundJson[0])
    $selectorTags = @($selectorTags[0])
}

$fallback = $selectorTags[0]
$selectorJson = ($selectorTags | ForEach-Object { Get-JsonString $_ }) -join ', '
$outboundsJoined = ($outboundJson -join ",`n")
$probe = Get-JsonString (Get-ProbeUrl)
$useBalancer = ($selectorTags.Count -gt 1)
$remarks = 'Otmena | vpn.dance | TG SOCKS 10808 + Cursor HTTP 10809 / SOCKS 10810'

if ($useBalancer) {
    $routingInner = @"
    "domainStrategy": "IPIfNonMatch",
    "balancers": [
      {
        "tag": "auto",
        "selector": [$selectorJson],
        "fallbackTag": $(Get-JsonString $fallback),
        "strategy": {
          "type": "leastPing"
        }
      }
    ],
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks-tg", "http-cursor", "socks-cursor"],
        "balancerTag": "auto"
      }
    ]
"@
    $observatoryBlock = @"
  "observatory": {
    "subjectSelector": [$selectorJson],
    "probeUrl": $probe,
    "probeInterval": "45s",
    "enableConcurrency": true
  },
"@
} else {
    $routingInner = @"
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["socks-tg", "http-cursor", "socks-cursor"],
        "outboundTag": $(Get-JsonString $fallback)
      }
    ]
"@
    $observatoryBlock = ''
}

$json = @"
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"]
  },
  "inbounds": [
    {
      "tag": "socks-tg",
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "http-cursor",
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "settings": {
        "allowTransparent": false
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    },
    {
      "tag": "socks-cursor",
      "listen": "127.0.0.1",
      "port": 10810,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
$outboundsJoined,
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
$routingInner
  },
$observatoryBlock
  "remarks": $(Get-JsonString $remarks)
}
"@

$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($configFile, $json, $utf8)

$meta = @{
    updated = (Get-Date).ToString('s')
    profiles = @($unique | ForEach-Object { '{0}:{1}/{2}' -f $_.Address, $_.Port, $_.Type })
    tags = $selectorTags
    fallback = $fallback
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText($metaFile, $meta, $utf8)

Say ("VLESS: {0} profilej, balancer {1}" -f $selectorTags.Count, ($selectorTags -join ', ')) Green
Write-Output ("VLESS_SYNC=ok profiles={0}" -f $selectorTags.Count)
exit 0
