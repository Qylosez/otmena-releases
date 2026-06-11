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

if ($Disable) {
    foreach ($k in @('http.proxy', 'http.proxySupport')) {
        if ($map.Contains($k)) { $map.Remove($k) }
    }
    Write-Note 'Cursor proxy otklyuchyon (pryamoe soedinenie).' Yellow
} else {
    $map['http.proxy'] = $proxyUrl
    $map['http.proxySupport'] = 'on'
    Write-Note "Cursor -> $proxyUrl (shifrovannyj tunnel, vyhod Polsha)." Green
}

$json = $map | ConvertTo-Json -Depth 20
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($settingsPath, $json, $utf8)

Write-Note 'Perezapusti Cursor, chtoby proksi primenilsya.' Cyan
exit 0
