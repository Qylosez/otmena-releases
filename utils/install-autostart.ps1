#Requires -Version 3.0
#Requires -RunAsAdministrator

$rootDir = Split-Path $PSScriptRoot -Parent
$gameFlag = Join-Path $rootDir 'utils\game_filter.enabled'
$launcher = Join-Path $PSScriptRoot 'launcher.ps1'
$ps = (Get-Command powershell.exe).Source

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }

function Register-Task([string]$name, [string]$execute, [string]$arguments, [string]$workDir, [bool]$highest) {
    $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName $name -Confirm:$false }

    $action = New-ScheduledTaskAction -Execute $execute -Argument $arguments -WorkingDirectory $workDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    if ($highest) {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    }
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    Write-Step "Task: $name"
}

try {
    Write-Host ''
    Write-Host '=== Avtozapusk (planirovshchik + avto-perekljuchenie) ===' -ForegroundColor Green
    Write-Host ''

    if (Test-Path $gameFlag) { Remove-Item $gameFlag -Force }

    cmd /c 'net stop zapret' 2>$null | Out-Null
    cmd /c 'sc delete zapret' 2>$null | Out-Null

    & (Join-Path $PSScriptRoot 'sync-service-args.ps1')

    Register-Task -name 'Otmena-Start' -execute $ps `
        -arguments "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`" -Action start -Quiet" `
        -workDir $rootDir -highest $true

    Write-Step 'Starting now...'
    & $launcher -Action start

    Write-Host ''
    Write-Host 'Gotovo. Pri vhode v Windows avtomat: DS/YT + Telegram.' -ForegroundColor Green
    Write-Host 'Esli sposob ne rabotaet - perekljuchaetsya na sledujushchij.' -ForegroundColor Gray
    Write-Host ''
    exit 0
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
