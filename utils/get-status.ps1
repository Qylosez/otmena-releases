#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

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
function Test-AutoPieces {
    $task = [bool](Get-ScheduledTask -TaskName 'Otmena-Start' -ErrorAction SilentlyContinue)
    if (-not $task) {
        $task = [bool](Get-ScheduledTask -TaskName 'Zapret-Start' -ErrorAction SilentlyContinue)
    }
    return @{
        Task = $task
        Startup = (Test-StartupAutostart)
        Run = (Test-OtmenaRunAutostart)
    }
}

$pieces = Test-AutoPieces
$autoFlag = Join-Path $PSScriptRoot 'autostart.on'
if (Test-Path -LiteralPath $autoFlag) {
    Enable-OtmenaStartupApproved -Folder 'StartupFolder' -Name 'Otmena.lnk'
    Enable-OtmenaStartupApproved -Folder 'Run' -Name 'Otmena'
    if (-not ($pieces.Task -or $pieces.Startup -or $pieces.Run)) {
        & (Join-Path $PSScriptRoot 'ensure-autostart.ps1') -Quiet | Out-Null
        $pieces = Test-AutoPieces
    }
}
$taskAuto = $pieces.Task
$startupAuto = $pieces.Startup
$runAuto = $pieces.Run
$autoType = 'none'
if ($taskAuto) { $autoType = 'task' }
elseif ($startupAuto) { $autoType = 'startup' }
elseif ($runAuto) { $autoType = 'run' }

Write-Output ("ZAPRET={0}" -f [int]$zapret)
Write-Output ("ZAPRET_ADMIN_OK={0}" -f [int]($isAdmin -or (Get-ScheduledTask -TaskName 'Otmena-Winws' -ErrorAction SilentlyContinue)))
Write-Output ("TG={0}" -f [int]($tgPort -or $tgProc))
Write-Output ("ADMIN={0}" -f [int]$isAdmin)
Write-Output ("AUTO={0}" -f [int]($taskAuto -or $startupAuto -or $runAuto))
Write-Output ("AUTO_TYPE={0}" -f $autoType)
Write-Output ("WORK={0}" -f [int]$workMode)
Write-Output ("XRAY={0}" -f [int](Test-Path (Join-Path $rootDir 'telegram-vless\bin\xray.exe')))
Write-Output ("TG_PORT={0}" -f [int](Test-PortListen 10808))
Write-Output ("TUNNEL={0}" -f [int](Test-PortListen 10809))
Write-Output ("TUNNEL_SOCKS={0}" -f [int](Test-PortListen 10810))
. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')
$cursorDiag = Get-CursorTunnelDiagnostics
Write-Output ("CURSOR={0}" -f [int](($cursorDiag.TUNNEL_UP -eq 1) -and ($cursorDiag.PROXY_SET -eq 1)))
Write-Output ("CURSOR_MODE={0}" -f $cursorDiag.MODE)
Write-Output ("CURSOR_PROXY={0}" -f $cursorDiag.PROXY_SET)
Write-Output ("CURSOR_SOCKS_LIVE={0}" -f $cursorDiag.SOCKS_LIVE)
Write-Output ("CURSOR_HTTP_LIVE={0}" -f $cursorDiag.HTTP_LIVE)
$subFile = Join-Path $rootDir 'telegram-vless\subscription.json'
Write-Output ("SUB={0}" -f [int](Test-Path $subFile))
