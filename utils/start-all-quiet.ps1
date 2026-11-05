#Requires -Version 3.0
# Logon entry. Waits for a network, repairs autostart, then runs a full Start.
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$lock = Join-Path $PSScriptRoot 'autostart-run.lock'
if (Test-Path -LiteralPath $lock) {
    $age = (Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime
    if ($age.TotalSeconds -lt 90) { exit 0 }
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$task = $null
try { $task = Get-ScheduledTask -TaskName 'Otmena-Start' -ErrorAction SilentlyContinue } catch {}
if (-not $isAdmin -and $task -and [string]$task.State -ne 'Disabled') { exit 0 }

try { Set-Content -LiteralPath $lock -Value (Get-Date -Format o) -Encoding ASCII } catch {}

if (-not (Test-OtmenaNetworkUp)) { Wait-OtmenaNetwork -Seconds 35 | Out-Null }

$flag = Join-Path $PSScriptRoot 'autostart.on'
if (Test-Path -LiteralPath $flag) {
    & (Join-Path $PSScriptRoot 'ensure-autostart.ps1') -Quiet | Out-Null
}

& (Join-Path $PSScriptRoot 'launcher.ps1') -Action start -Quiet
exit $LASTEXITCODE
