#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = Split-Path $PSScriptRoot -Parent
$xrayExe = Join-Path $rootDir 'telegram-vless\bin\xray.exe'

if (Test-Path $xrayExe) {
    Write-Output 'XRAY_OK=1'
    Write-Output ("XRAY_PATH={0}" -f $xrayExe)
    exit 0
}

if (-not $Quiet) {
    Write-Host 'Pervyj zapusk: ustanovka xray dlya Telegram...' -ForegroundColor Cyan
}

$install = Join-Path $PSScriptRoot 'install-xray.ps1'
& $install -Quiet
$code = $LASTEXITCODE

if (Test-Path $xrayExe) {
    Write-Output 'XRAY_OK=1'
    Write-Output ("XRAY_PATH={0}" -f $xrayExe)
    if (-not $Quiet) {
        Write-Host "xray gotov: $xrayExe" -ForegroundColor Green
    }
    exit 0
}

Write-Output 'XRAY_OK=0'
Write-Output ("XRAY_INSTALL_EXIT={0}" -f $code)
exit 1
