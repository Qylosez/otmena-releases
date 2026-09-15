#Requires -Version 3.0
# Point Cursor desktop at the local encrypted tunnel (xray HTTP inbound -> Poland Reality).
# Writes both settings.json (VS Code request stack) and argv.json (Electron/Chromium),
# otherwise Cursor Agent keeps going direct and loops on reconnect.
#
#   .\cursor-proxy.ps1            # enable  (http://127.0.0.1:10809)
#   .\cursor-proxy.ps1 -Disable   # restore previous Cursor proxy settings
#
param(
    [int]$Port = 10809,
    [switch]$Disable,
    [switch]$Quiet,
    [string]$SettingsPath,
    [string]$ArgvPath,
    [string]$StatePath
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Note($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

function Strip-Jsonc([string]$raw) {
    if (-not $raw) { return '' }
    $noBlock = [System.Text.RegularExpressions.Regex]::Replace($raw, '/\*.*?\*/', '', 'Singleline')
    return [System.Text.RegularExpressions.Regex]::Replace($noBlock, '(^|\s)//.*$', '$1', 'Multiline')
}

function Read-JsonMap([string]$path) {
    $map = [ordered]@{}
    if (-not (Test-Path $path)) { return $map }
    $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or -not $raw.Trim()) { return $map }
    try {
        $obj = (Strip-Jsonc $raw) | ConvertFrom-Json -ErrorAction Stop
        if ($obj) {
            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        }
    } catch {}
    return $map
}

function Write-JsonMap($map, [string]$path) {
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $map | ConvertTo-Json -Depth 20
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8)
}

function Get-Prop($map, [string]$name) {
    if ($map.Contains($name)) { return $map[$name] }
    return $null
}

if (-not $SettingsPath) {
    $SettingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
}
if (-not $ArgvPath) {
    $ArgvPath = Join-Path $env:USERPROFILE '.cursor\argv.json'
}
if (-not $StatePath) {
    $StatePath = Join-Path $PSScriptRoot 'cursor-proxy.state.json'
}

$proxyUrl = "http://127.0.0.1:$Port"
$settingsDir = Split-Path $SettingsPath -Parent
$cursorInstalled = Test-Path $settingsDir
if (-not $cursorInstalled -and -not $Disable) {
    Write-Note "Cursor ne ustanovlen (net $settingsDir) - propuskayu." Yellow
    Write-Output 'CURSOR_PROXY=skip'
    exit 0
}

$settingKeys = @(
    'http.proxy',
    'http.proxySupport',
    'http.proxyStrictSSL',
    'http.electronFetch',
    'cursor.general.disableHttp2'
)
$argvKeys = @('proxy-server', 'disable-http2')

$state = @{ enabled = $false; previous = @{}; previousArgv = @{} }
if (Test-Path $StatePath) {
    try {
        $loaded = Get-Content $StatePath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($loaded) {
            $state.enabled = [bool]$loaded.enabled
            if ($loaded.previous) {
                foreach ($p in $loaded.previous.PSObject.Properties) {
                    $state.previous[$p.Name] = $p.Value
                }
            }
            if ($loaded.previousArgv) {
                foreach ($p in $loaded.previousArgv.PSObject.Properties) {
                    $state.previousArgv[$p.Name] = $p.Value
                }
            }
        }
    } catch {}
}

$map = Read-JsonMap $SettingsPath
$argv = Read-JsonMap $ArgvPath

if ($Disable) {
    foreach ($k in $settingKeys) {
        if ($state.previous.Contains($k) -and $null -ne $state.previous[$k] -and [string]$state.previous[$k] -ne '') {
            $map[$k] = $state.previous[$k]
        } else {
            if ($map.Contains($k)) { $map.Remove($k) }
        }
    }
    foreach ($k in $argvKeys) {
        if ($state.previousArgv.Contains($k) -and $null -ne $state.previousArgv[$k] -and [string]$state.previousArgv[$k] -ne '') {
            $argv[$k] = $state.previousArgv[$k]
        } else {
            if ($argv.Contains($k)) { $argv.Remove($k) }
        }
    }
    if ($cursorInstalled) { Write-JsonMap $map $SettingsPath }
    if (Test-Path (Split-Path $ArgvPath -Parent) -or $argv.Count -gt 0) {
        if ($argv.Count -gt 0) { Write-JsonMap $argv $ArgvPath }
        elseif (Test-Path $ArgvPath) { Write-JsonMap $argv $ArgvPath }
    }
    $state.enabled = $false
    $state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8
    Write-Note 'Cursor proxy otklyuchyon (pryamoe soedinenie).' Yellow
    Write-Output 'CURSOR_PROXY=off'
    exit 0
}

if (-not $state.enabled) {
    foreach ($k in $settingKeys) {
        $state.previous[$k] = Get-Prop $map $k
    }
    foreach ($k in $argvKeys) {
        $state.previousArgv[$k] = Get-Prop $argv $k
    }
    $backup = "$SettingsPath.otmena.bak"
    if ((Test-Path $SettingsPath) -and -not (Test-Path $backup)) {
        Copy-Item $SettingsPath $backup -Force -ErrorAction SilentlyContinue
    }
}

$map['http.proxy'] = $proxyUrl
$map['http.proxySupport'] = 'override'
$map['http.proxyStrictSSL'] = $false
$map['http.electronFetch'] = $true
$map['cursor.general.disableHttp2'] = $true
$argv['proxy-server'] = $proxyUrl
$argv['disable-http2'] = $true

Write-JsonMap $map $SettingsPath
Write-JsonMap $argv $ArgvPath

$state.enabled = $true
$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StatePath -Encoding UTF8

Write-Note "Cursor -> $proxyUrl (Electron + settings, HTTP/2 vykl, vyhod Polsha)." Green
Write-Note 'Perezapusti Cursor, chtoby proksi primenilsya.' Cyan
Write-Output 'CURSOR_PROXY=on'
exit 0
