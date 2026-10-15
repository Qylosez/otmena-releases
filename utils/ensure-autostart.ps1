#Requires -Version 3.0
# Recreate every autostart hook: Startup shortcut, HKCU Run, and a logon task.
# Safe to call repeatedly. Does not start Otmena.
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = Split-Path $PSScriptRoot -Parent
$startupDir = [Environment]::GetFolderPath('Startup')
$linkPath = Join-Path $startupDir 'Otmena.lnk'
$ps = (Get-Command powershell.exe).Source
$target = Join-Path $PSScriptRoot 'start-all-quiet.ps1'
$winwsPs = Join-Path $PSScriptRoot 'start-winws.ps1'

function Say([string]$msg) {
    if (-not $Quiet) { Write-Host $msg }
}

try { & (Join-Path $PSScriptRoot 'sync-service-args.ps1') | Out-Null } catch {}

$shortcutOk = $false
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($linkPath)
    $shortcut.TargetPath = $ps
    $shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    $shortcut.WorkingDirectory = $rootDir
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'Otmena: DS/YT + Telegram + Cursor Europe'
    $shortcut.Save()
    $shortcutOk = $true
    Say "Startup shortcut: $linkPath"
} catch {
    Say "Shortcut failed: $($_.Exception.Message)"
}

$runOk = $false
try {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    $cmd = "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$target`""
    Set-ItemProperty -Path $runKey -Name 'Otmena' -Value $cmd
    $runOk = $true
    Say 'Run key: Otmena'
} catch {
    Say "Run key failed: $($_.Exception.Message)"
}

Enable-OtmenaStartupApproved -Folder 'StartupFolder' -Name 'Otmena.lnk'
Enable-OtmenaStartupApproved -Folder 'Run' -Name 'Otmena'

function Register-OtmenaTask([string]$name, [string]$scriptPath) {
    $argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principalUser = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $principalUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $level = if ($isAdmin) { 'Highest' } else { 'Limited' }
    try {
        $action = New-ScheduledTaskAction -Execute $ps -Argument $argLine -WorkingDirectory $rootDir
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        try { $trigger.Delay = 'PT20S' } catch {}
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel $level
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Force | Out-Null
        return $true
    } catch {
        Say "Task $name failed: $($_.Exception.Message)"
    }
    $rl = if ($isAdmin) { 'HIGHEST' } else { 'LIMITED' }
    $tr = "`"$ps`" $argLine"
    & schtasks.exe /Create /F /TN $name /SC ONLOGON /RL $rl /DELAY 0000:20 /TR $tr | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($rl -eq 'HIGHEST') {
        & schtasks.exe /Create /F /TN $name /SC ONLOGON /RL LIMITED /DELAY 0000:20 /TR $tr | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

$taskOk = Register-OtmenaTask -name 'Otmena-Start' -scriptPath $target
Register-OtmenaTask -name 'Otmena-Winws' -scriptPath $winwsPs | Out-Null

if ($taskOk) {
    Write-Output 'AUTOSTART=task'
    exit 0
}
if ($shortcutOk -or $runOk) {
    Write-Output 'AUTOSTART=startup'
    exit 0
}
Write-Output 'AUTOSTART=fail'
exit 1
