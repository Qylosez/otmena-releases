#Requires -Version 3.0
# Point Cursor desktop at the local encrypted tunnel (xray HTTP inbound -> Poland Reality).
# This makes Cursor (UI + all models) go out through Europe, encrypted, instead of
# straight through MTS where TSPU/RKN can throttle or block AI backends.
#
#   .\cursor-proxy.ps1            # enable  (http://127.0.0.1:10809)
#   .\cursor-proxy.ps1 -Disable   # remove the proxy from Cursor settings
#
# Cursor stores user settings at %APPDATA%\Cursor\User\settings.json (JSONC).
param(
    [int]$Port = 10809,
    [switch]$Disable,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Note($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

$proxyUrl = "http://127.0.0.1:$Port"
$settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
$settingsDir = Split-Path $settingsPath -Parent

if (-not (Test-Path $settingsDir)) {
    Write-Note "Cursor ne ustanovlen (net $settingsDir) - propuskayu." Yellow
    exit 0
}

# Load existing settings (strip // and /* */ comments so JSONC parses).
$settings = $null
if (Test-Path $settingsPath) {
    $raw = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
    if ($raw -and $raw.Trim()) {
        $noBlock = [System.Text.RegularExpressions.Regex]::Replace($raw, '/\*.*?\*/', '', 'Singleline')
        $noLine = [System.Text.RegularExpressions.Regex]::Replace($noBlock, '(^|\s)//.*$', '$1', 'Multiline')
        try { $settings = $noLine | ConvertFrom-Json -ErrorAction Stop } catch { $settings = $null }
    }
    # One-time backup before we rewrite the file.
    $backup = "$settingsPath.otmena.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item $settingsPath $backup -Force -ErrorAction SilentlyContinue
    }
}

# Normalise into an ordered hashtable we can edit predictably.
$map = [ordered]@{}
if ($settings) {
    foreach ($p in $settings.PSObject.Properties) { $map[$p.Name] = $p.Value }
}

# Keys we manage. Notes on why:
#  http.proxySupport = "override"  -> FORCE every request through the proxy. With "on"
#       Cursor may try a direct connection first and leak the real (RU/MTS) IP, which
#       triggers "model provider is not supported in your region".
#  cursor.general.disableHttp2 = true -> use HTTP/1.1. With HTTP/2 over a local proxy,
#       Cursor's streaming/region check can bypass the proxy and leak the real region.
#       This is THE documented fix for the region error behind a proxy/VPN.
#  http.proxyStrictSSL = false -> avoid TLS validation hiccups through the local proxy.
$managedKeys = @('http.proxy', 'http.proxySupport', 'http.proxyStrictSSL', 'cursor.general.disableHttp2')

if ($Disable) {
    foreach ($k in $managedKeys) {
        if ($map.Contains($k)) { $map.Remove($k) }
    }
    Write-Note 'Cursor proxy otklyuchyon (pryamoe soedinenie).' Yellow
} else {
    $map['http.proxy'] = $proxyUrl
    $map['http.proxySupport'] = 'override'
    $map['http.proxyStrictSSL'] = $false
    $map['cursor.general.disableHttp2'] = $true
    Write-Note "Cursor -> $proxyUrl (tunnel, vyhod Polsha; HTTP/2 off, proxy=override)." Green
}

$json = $map | ConvertTo-Json -Depth 20
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($settingsPath, $json, $utf8)

Write-Note 'Perezapusti Cursor, chtoby proksi primenilsya.' Cyan
exit 0
