#Requires -Version 3.0
param(
    [int]$Port = 10808,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

$uri = "tg://socks?server=127.0.0.1&port=$Port"
Start-Sleep -Milliseconds 300
$opened = Open-TgUriSafe -Uri $uri -Quiet:$Quiet -Kind 'socks'

if ($opened) {
    if (-not $Quiet) { Write-Host "SOCKS dobavlen v Telegram: 127.0.0.1:$Port" -ForegroundColor Green }
    exit 0
}

if (-not $Quiet) {
    Write-Host 'SOCKS vruchnuyu: 127.0.0.1 port 10808' -ForegroundColor Yellow
}
exit 2
