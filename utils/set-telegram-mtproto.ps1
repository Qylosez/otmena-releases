#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

$configFile = Join-Path $PSScriptRoot 'telegram-mtproto.json'
if (-not (Test-Path -LiteralPath $configFile)) {
    Write-Output 'ERROR=config missing'
    Write-Output 'STATUS=manual'
    exit 1
}

$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
$server = [string]$config.server
$port = [int]$config.port
$secret = [string]$config.secret

if (-not $server -or -not $port -or -not $secret) {
    Write-Output 'ERROR=invalid config'
    Write-Output 'STATUS=manual'
    exit 1
}

Write-Output ("SERVER={0}" -f $server)
Write-Output ("PORT={0}" -f $port)
Write-Output ("SECRET={0}" -f $secret)

$uri = "tg://proxy?server=$server&port=$port&secret=$secret"
$opened = Open-TgUriSafe -Uri $uri -Quiet:$Quiet -Kind 'mtproto'

if ($opened) {
    Write-Output 'STATUS=ok'
    Write-Output 'TG_OPEN=exe'
    if (-not $Quiet) {
        Write-Host "MTProto dobavlen: ${server}:$port" -ForegroundColor Green
        Write-Host 'Vklyuchi proksi v Telegram (Use proxy).' -ForegroundColor Yellow
    }
    exit 0
}

Write-Output 'STATUS=manual'
Write-Output 'MANUAL=1'
Write-Output ("MANUAL_SERVER={0}" -f $server)
Write-Output ("MANUAL_PORT={0}" -f $port)
Write-Output ("MANUAL_SECRET={0}" -f $secret)
if (-not $Quiet) {
    Write-Host 'Klyuch ne otkrylsya v Telegram Desktop' -ForegroundColor Yellow
    Write-Host ("Vruchnuyu MTProto: {0} port {1} secret {2}" -f $server, $port, $secret) -ForegroundColor Gray
}
exit 2
