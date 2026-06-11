#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(400, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Test-StartupAutostart {
    $startupDir = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
        if (Test-Path (Join-Path $startupDir $name)) { return $true }
    }
    return $false
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$zapret = [bool](Get-Process -Name winws -ErrorAction SilentlyContinue)
$tgPort = Test-PortListen 10808
$tgProc = [bool](Get-Process -Name xray -ErrorAction SilentlyContinue)
$workMode = Test-Path (Join-Path $PSScriptRoot 'work_mode.enabled')
$taskAuto = [bool](Get-ScheduledTask -TaskName 'Otmena-Start' -ErrorAction SilentlyContinue)
if (-not $taskAuto) {
    $taskAuto = [bool](Get-ScheduledTask -TaskName 'Zapret-Start' -ErrorAction SilentlyContinue)
}
$startupAuto = Test-StartupAutostart
$autoType = 'none'
if ($taskAuto) { $autoType = 'task' }
elseif ($startupAuto) { $autoType = 'startup' }

Write-Output ("ZAPRET={0}" -f [int]$zapret)
Write-Output ("TG={0}" -f [int]($tgPort -or $tgProc))
Write-Output ("ADMIN={0}" -f [int]$isAdmin)
Write-Output ("AUTO={0}" -f [int]($taskAuto -or $startupAuto))
Write-Output ("AUTO_TYPE={0}" -f $autoType)
Write-Output ("WORK={0}" -f [int]$workMode)
Write-Output ("XRAY={0}" -f [int](Test-Path (Join-Path $rootDir 'telegram-vless\bin\xray.exe')))
