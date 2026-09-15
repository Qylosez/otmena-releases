#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'work-mode.ps1')
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

function Write-Info([string]$msg) {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
}

if (Test-WinwsRunning) { exit 0 }

& (Join-Path $PSScriptRoot 'sync-service-args.ps1') 2>$null | Out-Null
Ensure-WlanApiDll $rootDir | Out-Null

$argsFile = Join-Path $PSScriptRoot 'alt11-service-args.txt'
$winws = Join-Path $rootDir 'bin\winws.exe'
if (-not (Test-Path $winws) -or -not (Test-Path $argsFile)) { exit 1 }

$raw = (Get-Content -LiteralPath $argsFile -Raw -ErrorAction SilentlyContinue)
if (-not $raw) { exit 1 }
$raw = $raw.Trim().Trim('"').Trim()

Start-OtmenaNativeProcess -FilePath $winws -Arguments $raw -WorkingDirectory (Join-Path $rootDir 'bin') | Out-Null
Start-Sleep -Seconds 3
if (Test-WinwsRunning) { exit 0 }

$bat = Join-Path $rootDir 'scripts\general (ALT11).bat'
if (Test-Path $bat) {
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$bat`"") -WorkingDirectory $rootDir -WindowStyle Hidden | Out-Null
    Start-Sleep -Seconds 3
}

if (Test-WinwsRunning) { exit 0 }
exit 1
