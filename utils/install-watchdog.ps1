#Requires -Version 3.0
# User-level repeating task. Does not need administrator.
param([switch]$Remove)

$ErrorActionPreference = 'SilentlyContinue'
$ps = (Get-Command powershell.exe).Source
$watchdog = Join-Path $PSScriptRoot 'watchdog.ps1'
$rootDir = Split-Path $PSScriptRoot -Parent
$name = 'Otmena-Watchdog'

Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
if ($Remove) {
    Write-Output 'WATCHDOG_TASK=removed'
    exit 0
}

try {
    $action = New-ScheduledTaskAction -Execute $ps `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdog`" -Quiet" `
        -WorkingDirectory $rootDir
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
    $logon = New-ScheduledTaskTrigger -AtLogOn
    try { $logon.Delay = 'PT25S' } catch {}
    $triggers = @($logon)
    try {
        $once = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
            -RepetitionInterval (New-TimeSpan -Minutes 2) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        $triggers = @($logon, $once)
    } catch {}
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $triggers `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Output 'WATCHDOG_TASK=ok'
    exit 0
} catch {
    Write-Output ("WATCHDOG_TASK=fail " + $_.Exception.Message)
    exit 1
}
