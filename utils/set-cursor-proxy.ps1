#Requires -Version 3.0
param(
    [string]$Host = '127.0.0.1',
    [int]$Port = 10808,
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'
if (-not (Test-Path $settingsPath)) {
    throw "Ne najden: $settingsPath"
}

$raw = Get-Content $settingsPath -Raw -Encoding UTF8
try {
    $json = $raw | ConvertFrom-Json
} catch {
    throw "Ne udalos prochitat settings.json: $($_.Exception.Message)"
}

if ($Disable) {
    $json.PSObject.Properties.Remove('http.proxy') | Out-Null
    $json.PSObject.Properties.Remove('http.proxySupport') | Out-Null
    $json.PSObject.Properties.Remove('http.proxyStrictSSL') | Out-Null
    $json | ConvertTo-Json -Depth 20 | Out-File -FilePath $settingsPath -Encoding UTF8 -Force
    Write-Host 'Cursor proxy vyklyuchen.' -ForegroundColor Yellow
    exit 0
}

$proxyUri = "socks5://${Host}:$Port"
$json | Add-Member -NotePropertyName 'http.proxy' -NotePropertyValue $proxyUri -Force
$json | Add-Member -NotePropertyName 'http.proxySupport' -NotePropertyValue 'override' -Force
$json | Add-Member -NotePropertyName 'http.proxyStrictSSL' -NotePropertyValue $false -Force

$json | ConvertTo-Json -Depth 20 | Out-File -FilePath $settingsPath -Encoding UTF8 -Force
Write-Host "Cursor proxy vklyuchen: $proxyUri" -ForegroundColor Green
Write-Host 'Perezapusti Cursor, chtoby primenilos.' -ForegroundColor Yellow
