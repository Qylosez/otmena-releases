#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

Write-Host 'Removing autostart...'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Unregister-ScheduledTask -TaskName 'Otmena-Start' -Confirm:$false
Unregister-ScheduledTask -TaskName 'Zapret-Start' -Confirm:$false
    Unregister-ScheduledTask -TaskName 'Zapret3-Telegram-Vless' -Confirm:$false
    Unregister-ScheduledTask -TaskName 'Zapret3-NoSystemProxy' -Confirm:$false
    Unregister-ScheduledTask -TaskName 'Zapret3-ALT11' -Confirm:$false

    cmd /c 'net stop zapret' 2>$null | Out-Null
    cmd /c 'sc delete zapret' 2>$null | Out-Null
}

$startupDir = [Environment]::GetFolderPath('Startup')
foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
    $link = Join-Path $startupDir $name
    if (Test-Path $link) { Remove-Item $link -Force }
}

& (Join-Path $PSScriptRoot 'launcher.ps1') -Action stop -Quiet
Write-Host 'Done.'
