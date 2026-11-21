#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

Write-Host 'Removing autostart...'

$flag = Join-Path $PSScriptRoot 'autostart.on'
if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force }

Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Otmena' -ErrorAction SilentlyContinue

foreach ($name in @('Otmena-Start', 'Otmena-Winws', 'Zapret-Start', 'Zapret3-Telegram-Vless', 'Zapret3-NoSystemProxy', 'Zapret3-ALT11')) {
    & schtasks.exe /Delete /TN $name /F 2>$null | Out-Null
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    cmd /c 'net stop zapret' 2>$null | Out-Null
    cmd /c 'sc delete zapret' 2>$null | Out-Null
}

$startupDir = [Environment]::GetFolderPath('Startup')
foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
    $link = Join-Path $startupDir $name
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
}

& (Join-Path $PSScriptRoot 'launcher.ps1') -Action stop -Quiet
Write-Host 'Done.'
