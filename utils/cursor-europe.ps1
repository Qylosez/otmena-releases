#Requires -Version 3.0
<#
  Cursor -> Europe one-click connector.

  Why this exists: setting only "http.proxy" inside Cursor's settings.json is not
  always honoured by Cursor/Electron for every socket. The reliable way on Windows
  is the *system proxy* (WinINet) which Chromium/Electron (and therefore Cursor)
  respects. This script:
    1. starts the local xray tunnel (vpn.dance) if it is not already up,
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
    [switch]$Quiet,
    [switch]$SettingsOnly
)

$ErrorActionPreference = 'SilentlyContinue'
$utilsDir = $PSScriptRoot
$rootDir = Split-Path $utilsDir -Parent
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

. (Join-Path $utilsDir 'cursor-tunnel.ps1')

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
    $proxy = "http://127.0.0.1:$p"
    foreach ($url in @('https://ipinfo.io/json', 'https://ipapi.co/json')) {
        try {
            $json = & curl.exe -s --max-time 12 -x $proxy $url
            if ($json) {
                $obj = $json | ConvertFrom-Json
                if ($obj.ip -and $obj.country) { return $obj }
                if ($obj.ip -and $obj.country_code) {
                    return [PSCustomObject]@{ ip = $obj.ip; city = $obj.city; country = $obj.country_code }
                }
            }
        } catch {}
    }
    try {
        $trace = & curl.exe -s --max-time 12 -x $proxy https://1.1.1.1/cdn-cgi/trace
        if ($trace -match '(?m)^ip=(.+)$') {
            $ip = $matches[1].Trim()
            $cc = ''
            $city = ''
            if ($trace -match '(?m)^loc=(.+)$') { $cc = $matches[1].Trim() }
            if ($trace -match '(?m)^colo=(.+)$') { $city = $matches[1].Trim() }
            if ($ip) { return [PSCustomObject]@{ ip = $ip; city = $city; country = $cc } }
        }
    } catch {}
    return $null
}

if ($Off) {
    Say 'Vyklyuchayu Cursor->Europe (pryamoe soedinenie)...' Yellow
    Stop-CursorWatch
    Set-SystemProxyOff
    Disable-CursorTunnelProxy -Quiet:$Quiet
    Say 'Gotovo. Sistemnyj proksi vyklyuchen. Perezapusti Cursor.' Green
    exit 0
}

Say '=== Cursor -> Europe (vpn.dance) ===' Cyan

if (-not (Test-PortListen 10808) -and -not (Test-PortListen 10810) -and -not (Test-PortListen 10809)) {
    Say 'Podnimayu tunnel (xray)...'
    & (Join-Path $utilsDir 'telegram-vless-daemon.ps1') -Quiet | Out-Null
    Start-Sleep -Seconds 2
}
$mode = Get-CursorTunnelEndpoint
if (-not $mode) {
    Say 'Tunnel ne otvechaet. Zapusti Otmena -> Zapustit (nuzhen rabochij xray na 10808).' Red
    Disable-CursorTunnelProxy -Quiet:$Quiet
    exit 1
}
$usePort = $mode.Port
Say ("Tunnel OK: {0} {1}://127.0.0.1:{2}" -f $mode.Label, $mode.Mode, $usePort) Green

# 2. Cursor settings (and optional WinINet system proxy).
if ($SettingsOnly) {
    if (Enable-CursorTunnelProxy -Quiet:$Quiet) {
        Say ("Cursor settings -> {0}://127.0.0.1:{1} ({2}). Sistemnyj proksi ne trogayu." -f $mode.Mode, $usePort, $mode.Label) Green
    } else {
        Say 'Ne udalos vklyuchit proksi v Cursor.' Red
        exit 1
    }
} else {
    if (-not (Enable-CursorTunnelProxy -Quiet:$Quiet)) {
        Say 'Ne udalos vklyuchit proksi v Cursor.' Red
        exit 1
    }
    Set-SystemProxyOn $usePort
    Say "Sistemnyj proksi -> 127.0.0.1:$usePort (Cursor i brauzery poidut cherez tunnel)." Green
}

# 3. Verify egress.
$info = Get-ExitInfo $usePort
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
