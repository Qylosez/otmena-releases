#Requires -Version 3.0
param(
    [string]$TargetFolder,
    [string]$OutZip
)

$ErrorActionPreference = 'Stop'
$rootDir = Split-Path $PSScriptRoot -Parent

if (-not $TargetFolder) {
  throw 'Ukazhi -TargetFolder (papka Otmena na PK polzovatelya)'
}

$TargetFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetFolder)
if (-not (Test-Path $TargetFolder)) {
  throw "Papka ne naidena: $TargetFolder"
}

$files = @(
    'Otmena.exe',
    'utils\app.version',
    'utils\BUILDINFO.txt',
    'utils\otmena-common.ps1',
    'utils\telegram-uri.ps1',
    'utils\set-telegram-mtproto.ps1',
    'utils\set-telegram-socks.ps1',
    'utils\launcher.ps1',
    'utils\ensure-xray.ps1',
    'utils\install-xray.ps1',
    'utils\check-updates.ps1',
    'utils\apply-update.ps1',
    'utils\export-diagnostics.ps1',
    'utils\get-status.ps1',
    'utils\detect-environment.ps1',
    'utils\update-config.json',
    'utils\telegram-mtproto.json',
    'utils\install-user-autostart.ps1',
    'utils\start-all-quiet.ps1',
    'utils\telegram-vless-daemon.ps1'
)

$copied = 0
foreach ($rel in $files) {
    $src = Join-Path $rootDir $rel
    if (-not (Test-Path $src)) {
        Write-Host "SKIP (net v sborki): $rel" -ForegroundColor Yellow
        continue
    }
    $dst = Join-Path $TargetFolder $rel
    $parent = Split-Path $dst -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "OK $rel" -ForegroundColor Green
    $copied++
}

$skipOnTarget = Join-Path $TargetFolder 'utils\skip-xray.flag'
if (Test-Path $skipOnTarget) {
    Remove-Item $skipOnTarget -Force
    Write-Host 'Removed utils\skip-xray.flag (blokiroval ustanovku xray)' -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Gotovo: $copied fajlov -> $TargetFolder" -ForegroundColor Green

if ($OutZip) {
    $temp = Join-Path $env:TEMP ('otmena-hotfix-' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    foreach ($rel in $files) {
        $src = Join-Path $rootDir $rel
        if (Test-Path $src) {
            $d = Join-Path $temp $rel
            $p = Split-Path $d -Parent
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
            Copy-Item -Path $src -Destination $d -Force
        }
    }
    if (Test-Path $OutZip) { Remove-Item $OutZip -Force }
    Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $OutZip -Force
    Remove-Item $temp -Recurse -Force
    Write-Host "Zip: $OutZip" -ForegroundColor Cyan
}
