#Requires -Version 3.0
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$globalDir = Join-Path $env:APPDATA 'Cursor\User\globalStorage'
$db = Join-Path $globalDir 'state.vscdb'
$wal = "$db-wal"
$shm = "$db-shm"

if (-not (Test-Path $db)) {
    Write-Host 'state.vscdb ne najden — ochistka ne nuzhna.' -ForegroundColor Yellow
    exit 0
}

$sizeGb = [math]::Round((Get-Item $db).Length / 1GB, 2)
Write-Host "Tekushchij razmer state.vscdb: $sizeGb GB" -ForegroundColor Cyan

$cursorProcs = Get-Process Cursor -ErrorAction SilentlyContinue
if ($cursorProcs -and -not $Force) {
    Write-Host 'Zakroi Cursor polnostyu i zapusti skript snova.' -ForegroundColor Red
    Write-Host 'Ili: fix-cursor-cache.ps1 -Force' -ForegroundColor Gray
    exit 2
}

if ($cursorProcs) {
    Write-Host 'Ostanavlivayu Cursor...' -ForegroundColor Yellow
    $cursorProcs | Stop-Process -Force
    Start-Sleep -Seconds 3
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $globalDir "state.vscdb.bloated-$stamp"
Write-Host "Pereimenovyvayu staryj state.vscdb -> $(Split-Path $backup -Leaf)" -ForegroundColor Yellow
Move-Item -Path $db -Destination $backup -Force

foreach ($extra in @($wal, $shm)) {
    if (Test-Path $extra) {
        Remove-Item $extra -Force
    }
}

Write-Host 'Gotovo. Pri sleduyushchem zapuske Cursor sozdast novyj state.vscdb.' -ForegroundColor Green
Write-Host 'Mozhet ponadobitsya povtornyj vhod v akkaunt.' -ForegroundColor Yellow
Write-Host "Staryj fajl sohranen: $backup" -ForegroundColor Gray
