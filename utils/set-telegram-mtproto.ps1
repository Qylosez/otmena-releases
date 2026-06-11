#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

$configFile = Join-Path $PSScriptRoot 'telegram-mtproto.json'
if (-not (Test-Path $configFile)) {
    Write-Output 'ERROR=config missing'
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json
$server = [string]$config.server
$port = [int]$config.port
$secret = [string]$config.secret

if (-not $server -or -not $port -or -not $secret) {
    Write-Output 'ERROR=invalid config'
    exit 1
}

Write-Output ("SERVER={0}" -f $server)
Write-Output ("PORT={0}" -f $port)
Write-Output ("SECRET={0}" -f $secret)

function Start-TelegramDesktop {
    foreach ($p in (Get-TelegramDesktopCandidates)) {
        if (-not (Test-OtmenaPath $p)) { continue }
        try {
            Start-Process -FilePath $p | Out-Null
            Start-Sleep -Seconds 2
            return $true
        } catch {}
    }
    return $false
}

$tgStarted = Start-TelegramDesktop
if ($tgStarted) { Write-Output 'TELEGRAM=started' }

$uri = "tg://proxy?server=$server&port=$port&secret=$secret"
$opened = $false

if (Test-TgUriHandler) {
    $opened = Open-TgUriSafe -Uri $uri -Quiet:$Quiet -Kind 'mtproto'
} elseif ($tgStarted) {
    try {
        Start-Process $uri | Out-Null
        Start-Sleep -Seconds 1
        $opened = $true
    } catch {}
}

if ($opened) {
    Write-Output 'STATUS=ok'
    if (-not $Quiet) {
        Write-Host "MTProto dobavlen: ${server}:$port" -ForegroundColor Green
        Write-Host 'Vklyuchi proksi v Telegram (Use proxy).' -ForegroundColor Yellow
    }
    exit 0
}

Write-Output 'STATUS=manual'
Write-Output 'MANUAL=1'
if (-not $Quiet) {
    Write-Host 'Telegram Desktop ne privyazan k tg://' -ForegroundColor Yellow
    Write-Host 'Nastroj vruchnuyu: Nastrojki -> Proksi -> MTProto' -ForegroundColor Gray
}
exit 2
