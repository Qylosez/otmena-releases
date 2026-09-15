#Requires -Version 3.0
param(
    [switch]$DeleteFolder,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $PSScriptRoot 'launcher.ps1'

function Write-Step([string]$msg) {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
}

Write-Step 'Ostanovka zapret i Telegram...'
& $launcher -Action stop -Quiet

Write-Step 'Udalenie avtozapuska...'
Unregister-ScheduledTask -TaskName 'Otmena-Start' -Confirm:$false
Unregister-ScheduledTask -TaskName 'Zapret-Start' -Confirm:$false
Unregister-ScheduledTask -TaskName 'Zapret3-Telegram-Vless' -Confirm:$false
Unregister-ScheduledTask -TaskName 'Zapret3-NoSystemProxy' -Confirm:$false
Unregister-ScheduledTask -TaskName 'Zapret3-ALT11' -Confirm:$false

$startupDir = [Environment]::GetFolderPath('Startup')
foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
    $link = Join-Path $startupDir $name
    if (Test-Path $link) { Remove-Item $link -Force }
}

cmd /c 'net stop zapret' 2>$null | Out-Null
cmd /c 'sc delete zapret' 2>$null | Out-Null
cmd /c 'net stop WinDivert' 2>$null | Out-Null
cmd /c 'sc delete WinDivert' 2>$null | Out-Null

taskkill /IM winws.exe /F 2>$null | Out-Null
taskkill /IM xray.exe /F 2>$null | Out-Null
if ($DeleteFolder) {
    taskkill /IM Otmena.exe /F 2>$null | Out-Null
    taskkill /IM Zapret.exe /F 2>$null | Out-Null
}

& (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')

if ($DeleteFolder) {
    $workFlag = Join-Path $PSScriptRoot 'work_mode.enabled'
    if (Test-Path $workFlag) { Remove-Item $workFlag -Force }
}

Write-Step 'Gotovo: vse ostanovleno i otvyazano ot avtozapuska.'

if (-not $DeleteFolder) {
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Papku mozhno udalit vruchnuyu ili zapusti:' -ForegroundColor Gray
        Write-Host "  uninstall-all.ps1 -DeleteFolder" -ForegroundColor Gray
    }
    exit 0
}

Write-Step "Udalenie papki: $rootDir"
$escaped = $rootDir.Replace("'", "''")
$deleteCmd = @"
Start-Sleep -Seconds 2
Remove-Item -LiteralPath '$escaped' -Recurse -Force -ErrorAction SilentlyContinue
"@

Start-Process powershell.exe -ArgumentList @(
    '-NoProfile', '-WindowStyle', 'Hidden', '-Command', $deleteCmd
) -WindowStyle Hidden | Out-Null

if (-not $Quiet) {
    Write-Host 'Papka budet udalena cherez 2 sek. Okno mozhno zakryt.' -ForegroundColor Yellow
}

exit 0
