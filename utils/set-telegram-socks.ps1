#Requires -Version 3.0
param(
    [int]$Port = 10808,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

$uri = "tg://socks?server=127.0.0.1&port=$Port"
$opened = Open-TgUriSafe -Uri $uri -Quiet:$Quiet -Kind 'socks'

if ($opened) {
    Write-Output 'STATUS=ok'
    Write-Output 'TG_OPEN=exe'
    if (-not $Quiet) {
        Write-Host "SOCKS dobavlen v Telegram: 127.0.0.1:$Port" -ForegroundColor Green
        Write-Host 'Esli vyshel toast "Nekorrektnaja ssylka" — nastroj vruchnuyu (okno s instrukciej).' -ForegroundColor Yellow
        Show-TelegramSocksManual -Port $Port
    }
    exit 0
}

Write-Output 'STATUS=manual'
Write-Output 'MANUAL=1'
Write-Output ("MANUAL_SOCKS=127.0.0.1:{0}" -f $Port)
if (-not $Quiet) {
    Show-TelegramSocksManual -Port $Port
}
exit 2
