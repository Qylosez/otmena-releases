#Requires -Version 3.0
# Point Cursor desktop at the local encrypted tunnel (xray -> vpn.dance).
param(
    [ValidateSet('socks', 'http')]
    [string]$Mode = 'socks',
    [int]$Port = 0,
    [string]$Label = 'manual',
    [switch]$Disable,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')

function Write-Note($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

function Set-JsonMapFile([string]$path, [scriptblock]$edit, [switch]$Create) {
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        if (-not $Create) { return $false }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $map = [ordered]@{}
    if (Test-Path $path) {
        $raw = Get-Content $path -Raw -ErrorAction SilentlyContinue
        $obj = ConvertFrom-Jsonc $raw
        if ($obj) {
            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        } elseif ($raw -and $raw.Trim()) {
            return $false
        }
        $backup = "$path.otmena.bak"
        if (-not (Test-Path $backup)) {
            Copy-Item $path $backup -Force -ErrorAction SilentlyContinue
        }
    } elseif (-not $Create) {
        return $false
    }
    & $edit $map | Out-Null
    $json = $map | ConvertTo-Json -Depth 20
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $json, $utf8)
    return $true
}

if (-not $Port) {
    $Port = if ($Mode -eq 'socks') { 10808 } else { 10809 }
}

$proxyUrl = if ($Mode -eq 'socks') {
    "socks5://127.0.0.1:$Port"
} else {
    "http://127.0.0.1:$Port"
}

$settingsPaths = @(
    (Join-Path $env:APPDATA 'Cursor\User\settings.json'),
    (Join-Path $env:APPDATA 'Cursor Nightly\User\settings.json')
)

$wrote = $false
foreach ($settingsPath in $settingsPaths) {
    $ok = Set-JsonMapFile $settingsPath -Create:($settingsPath -like '*\Cursor\User\settings.json') -edit {
        param($map)
        if ($Disable) {
            foreach ($k in @('http.proxy', 'http.proxySupport', 'http.noProxy', 'http.proxyStrictSSL', 'http.electronFetch', 'cursor.general.disableHttp2')) {
                if ($map.Contains($k)) { $map.Remove($k) }
            }
        } else {
            $map['http.proxy'] = $proxyUrl
            $map['http.proxySupport'] = 'override'
            $map['http.noProxy'] = 'localhost,127.0.0.1,::1'
            $map['http.proxyStrictSSL'] = $false
            $map['http.electronFetch'] = $true
            $map['cursor.general.disableHttp2'] = $true
        }
    }
    if ($ok) { $wrote = $true }
}

$argvPath = Join-Path $env:USERPROFILE '.cursor\argv.json'
if ($Disable) {
    Set-JsonMapFile $argvPath -edit {
        param($map)
        foreach ($k in @('proxy-server', 'disable-http2')) {
            if ($map.Contains($k)) { $map.Remove($k) }
        }
    } | Out-Null
} elseif ($wrote) {
    Set-JsonMapFile $argvPath -Create -edit {
        param($map)
        $map['proxy-server'] = $proxyUrl
        $map['disable-http2'] = $true
    } | Out-Null
}

if ($Disable) {
    Write-Note 'Cursor proxy otklyuchyon (pryamoe soedinenie).' Yellow
    Set-CursorProxyState -enabledByOtmena:$false -Mode 'none'
} elseif ($wrote) {
    Write-Note "Cursor -> $proxyUrl ($Label). POLNOSTYU zakroj i otkroj Cursor." Green
    Set-CursorProxyState -enabledByOtmena:$true -Mode $Mode -Port $Port -Label $Label -MarkOk
} else {
    Write-Note 'Cursor settings.json ne najden - zapusti Cursor odin raz, potom Otmena snova.' Yellow
    exit 1
}
exit 0
