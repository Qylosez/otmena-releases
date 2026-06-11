#Requires -Version 3.0
<#
  Cursor -> Europe (Poland) one-click connector.

  Why this exists: setting only "http.proxy" inside Cursor's settings.json is not
  always honoured by Cursor/Electron for every socket. The reliable way on Windows
  is the *system proxy* (WinINet) which Chromium/Electron (and therefore Cursor)
  respects. This script:
    1. starts the local xray tunnel (Poland Reality) if it is not already up,
    2. points the Windows system proxy AND Cursor settings at 127.0.0.1:10809,
    3. verifies the real egress IP is in Europe,
    4. -Off restores a direct connection.

  Usage:
    powershell -ExecutionPolicy Bypass -File utils\cursor-europe.ps1
    powershell -ExecutionPolicy Bypass -File utils\cursor-europe.ps1 -Off
#>
param(
    [int]$Port = 10809,
    [switch]$Off,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$utilsDir = $PSScriptRoot
$rootDir = Split-Path $utilsDir -Parent
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Say($msg, $color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

function Test-PortListen([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $p, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(1500, $false) -and $c.Connected) { $c.Close(); return $true }
        $c.Close()
    } catch {}
    return $false
}

# Tell WinINet that proxy settings changed so apps pick it up without a reboot.
function Update-WinInet {
    $sig = @'
[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
    try {
        $w = Add-Type -MemberDefinition $sig -Name 'WinInetCE' -Namespace 'Otmena' -PassThru -ErrorAction Stop
        $w::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null  # SETTINGS_CHANGED
        $w::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null  # REFRESH
    } catch {}
}

function Set-SystemProxyOn([int]$p) {
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value "127.0.0.1:$p" -Type String -Force
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value '<local>;localhost;127.*;10.*;172.16.*;192.168.*' -Type String -Force
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1 -Type DWord -Force
    Remove-ItemProperty -Path $regPath -Name AutoConfigURL -ErrorAction SilentlyContinue
    Update-WinInet
}

function Set-SystemProxyOff {
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -Type DWord -Force
    Remove-ItemProperty -Path $regPath -Name ProxyServer -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $regPath -Name ProxyOverride -ErrorAction SilentlyContinue
    Update-WinInet
}

function Get-ExitInfo([int]$p) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { return $null }
    try {
        $json = & curl.exe -s --max-time 20 -x "http://127.0.0.1:$p" https://ipinfo.io/json
        if ($json) { return ($json | ConvertFrom-Json) }
    } catch {}
    return $null
}

if ($Off) {
    Say 'Vyklyuchayu Cursor->Europe (pryamoe soedinenie)...' Yellow
    Set-SystemProxyOff
    & (Join-Path $utilsDir 'cursor-proxy.ps1') -Disable -Quiet:$Quiet 2>$null | Out-Null
    Say 'Gotovo. Sistemnyj proksi vyklyuchen. Perezapusti Cursor.' Green
    exit 0
}

Say '=== Cursor -> Europe (Poland) ===' Cyan

# 1. Bring the tunnel up (same xray process serves 10808/10809/10810).
if (-not (Test-PortListen $Port)) {
    Say 'Podnimayu tunnel (xray)...'
    & (Join-Path $utilsDir 'telegram-vless-daemon.ps1') -Quiet | Out-Null
    Start-Sleep -Seconds 2
}
if (-not (Test-PortListen $Port)) {
    Say "Tunnel ne podnyalsya (port $Port zakryt). Zapusti Otmena.exe -> Zapustit, ili proverь xray." Red
    exit 1
}
Say "Tunnel OK: 127.0.0.1:$Port" Green

# 2. Point both system proxy and Cursor settings at the tunnel.
Set-SystemProxyOn $Port
& (Join-Path $utilsDir 'cursor-proxy.ps1') -Port $Port -Quiet:$Quiet 2>$null | Out-Null
Say "Sistemnyj proksi -> 127.0.0.1:$Port (Cursor i brauzery poidut cherez Polshu)." Green

# 3. Verify egress.
$info = Get-ExitInfo $Port
if ($info -and $info.ip) {
    $loc = ("{0} {1} {2}" -f $info.ip, $info.city, $info.country).Trim()
    if ($info.country -eq 'RU') {
        Say "VNIMANIE: vyhod vsyo eshchyo Rossiya ($loc) - tunnel ne rabotaet!" Red
    } else {
        Say "Proverka OK: vyhod $loc (ne Rossiya)." Green
    }
} else {
    Say 'Ne udalos proverit vyhod cherez curl (no proksi nastroen).' Yellow
}

Say '' 
Say 'VAZHNO: polnostyu zakroj i snova otkroj Cursor, chtoby proksi primenilsya.' Cyan
Say 'Otklyuchit: cursor-europe.ps1 -Off (ili knopka Ostanovit v Otmena).' Gray
exit 0
