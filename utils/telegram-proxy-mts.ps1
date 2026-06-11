param(
    [switch]$Blind,
    [int]$BlindCount = 8
)

$env:TELEGRAM_MTS = '1'
$script = Join-Path $PSScriptRoot 'telegram-proxy.ps1'
$cmd = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $script,
    'mts'
)
if ($Blind) { $cmd += '-Blind' }
if ($BlindCount -ne 8) { $cmd += '-BlindCount'; $cmd += $BlindCount }
& powershell.exe @cmd
exit $LASTEXITCODE
