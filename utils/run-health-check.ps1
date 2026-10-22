#Requires -Version 3.0
# Human + machine readable health check for Otmena (GUI, CHECK.bat, diagnostics).
param(
    [switch]$Quiet,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'otmena-common.ps1')
. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')

$issues = New-Object System.Collections.Generic.List[string]
$oks = New-Object System.Collections.Generic.List[string]
$fixes = New-Object System.Collections.Generic.List[string]

function Add-Ok([string]$area, [string]$msg) {
    $oks.Add("[$area] $msg")
    Write-Output ("CHECK_OK={0}|{1}" -f $area, $msg)
}

function Add-Fail([string]$area, [string]$msg, [string]$fix) {
    $issues.Add("[$area] $msg")
    $fixes.Add("[$area] $fix")
    Write-Output ("CHECK_FAIL={0}|{1}" -f $area, $msg)
    Write-Output ("CHECK_FIX={0}|{1}" -f $area, $fix)
}

function Test-SystemProxyOn {
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        return ([int]$reg.ProxyEnable -eq 1 -and $reg.ProxyServer)
    } catch { return $false }
}

function Get-SystemProxyServer {
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$reg.ProxyEnable -eq 1) { return [string]$reg.ProxyServer }
    } catch {}
    return ''
}

# --- Collect raw status ---
$envLines = & (Join-Path $PSScriptRoot 'detect-environment.ps1')
$statusLines = & (Join-Path $PSScriptRoot 'get-status.ps1')
$diag = Get-CursorTunnelDiagnostics

$map = @{}
foreach ($line in ($envLines + $statusLines)) {
    if ($line -match '^([^=]+)=(.*)$') { $map[$matches[1]] = $matches[2] }
}

$ver = Get-OtmenaAppVersion

# --- Zapret / DS / YT ---
if ($map['ZAPRET'] -eq '1') {
    Add-Ok 'DS/YT' 'winws (zapret) zapushchen'
} else {
    $fix = 'Zapusti Otmena ot imeni administratora ili ZAPRET-ADMIN.bat'
    if ($map['ADMIN'] -ne '1') { $fix = 'PKM na Otmena.exe -> Zapusk ot imeni administratora, zatem ZAPRET-ADMIN.bat' }
    Add-Fail 'DS/YT' 'winws ne rabotaet — YouTube i Discord vyklyucheny' $fix
}

# --- Telegram / xray ---
if ($map['TG_PORT'] -eq '1') {
    Add-Ok 'Telegram' 'SOCKS 127.0.0.1:10808 slushaet'
} elseif ($map['TG'] -eq '1') {
    Add-Ok 'Telegram' 'xray/process est, no port 10808 ne otvetil'
} else {
    Add-Fail 'Telegram' 'Net tunelya vpn.dance (xray)' 'Otmena -> Zapustit; esli ne pomogaet — obnovi podpisku (Obnovleniya)'
}

if ($map['XRAY'] -ne '1') {
    Add-Fail 'Xray' 'net xray.exe' 'Obnovleniya v Otmena ili polozhi xray v telegram-vless\bin'
}

# --- Cursor tunnel ---
$ep = Get-CursorTunnelEndpoint
$settingsProxy = Get-CursorSettingsProxyUrl
$expectedProxy = Get-CursorProxyUrl

if (-not $ep) {
    Add-Fail 'Cursor' 'Tunnel ne otvechaet (api2.cursor.sh cherez proksi)' 'CURSOR-WORK.bat -> File->Exit v Cursor -> otkroj snova'
} elseif ($diag['SOCKS_LIVE'] -eq 1) {
    Add-Ok 'Cursor' ("SOCKS 10808 zhivoy ({0})" -f $ep.Label)
} elseif ($diag['HTTP_LIVE'] -eq 1) {
    Add-Ok 'Cursor' ("HTTP 10809 zhivoy ({0})" -f $ep.Label)
} elseif ($diag['TG_LISTEN'] -eq 1 -and $diag['XRAY'] -eq 1) {
    Add-Fail 'Cursor' 'Port otkryt, no internet cherez VPN ne idet' 'find-working-vless: zapusti CURSOR-WORK.bat; esli fail — HOTSPOT s telefona'
} else {
    Add-Fail 'Cursor' 'Net rabochego endpoint dlya Cursor' 'CURSOR-WORK.bat'
}

if ($diag['PROXY_SET'] -ne 1) {
    Add-Fail 'Cursor' 'V Cursor settings.json net proksi' 'CURSOR-WORK.bat i polnyj perezapusk Cursor'
} elseif ($settingsProxy -and $expectedProxy -and ($settingsProxy -ne $expectedProxy)) {
    Add-Fail 'Cursor' ("Rassinhron proksi: fajl=$settingsProxy ozhidaetsya=$expectedProxy") 'CURSOR-WORK.bat'
} elseif ($settingsProxy -match 'socks5h') {
    Add-Fail 'Cursor' 'Uстаревший socks5h v settings (Cursor ne ponimaet)' 'CURSOR-WORK.bat'
} else {
    Add-Ok 'Cursor' ("settings.json: $settingsProxy")
}

if (Test-WorkModeEnabled) {
    $sys = Get-SystemProxyServer
    if (Test-SystemProxyOn) {
        Add-Ok 'Cursor' ("Sistemnyj proksi: $sys")
    } else {
        Add-Fail 'Cursor' 'VM/rabochij rezhim: sistemnyj proksi vyklyuchen' 'CURSOR-WORK.bat (vklyuchit 127.0.0.1:10809)'
    }
}

$cursorProc = [bool](Get-Process -Name Cursor -ErrorAction SilentlyContinue)
if ($cursorProc -and $diag['PROXY_SET'] -eq 1 -and -not $ep) {
    Add-Fail 'Cursor' 'Cursor otkryt, no tunnel mertv — budet vechnoe perepodklyuchenie' 'Zakroj Cursor, CURSOR-WORK.bat, otkroj snova'
}

# --- Environment hints ---
if ($map['WORK'] -eq '1') {
    Add-Ok 'Sreda' 'Work mode (VM / bez sluzhby Windows)'
}
if ($map['AUTO_TYPE'] -eq 'startup' -and $map['ADMIN'] -ne '1') {
    Add-Fail 'Avtozapusk' 'Avtozapusk cherez Startup bez admin — winws ne podnimetsya' 'scripts\USTANOVIT-AUTOZAPUSK.bat ot administratora'
}

# --- Build human report ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Otmena: proverka ===')
[void]$sb.AppendLine(("Versiya: {0} | {1}" -f $ver, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
[void]$sb.AppendLine('')

if ($issues.Count -eq 0) {
    [void]$sb.AppendLine('Vse proverki proshli. Esli Cursor vse ravno ne rabotaet — polnostyu zakroj i otkroj ego (File -> Exit).')
} else {
    [void]$sb.AppendLine(('PROBLEM: {0}' -f $issues.Count))
    foreach ($i in $issues) { [void]$sb.AppendLine("  ! $i") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('CHTO DELAT:')
    $shown = @{}
    foreach ($f in $fixes) {
        if ($shown.ContainsKey($f)) { continue }
        $shown[$f] = $true
        [void]$sb.AppendLine("  -> $f")
    }
}

if ($oks.Count -gt 0) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('OK:')
    foreach ($o in $oks) { [void]$sb.AppendLine("  + $o") }
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- technika ---')
[void]$sb.AppendLine(("ENDPOINT={0}" -f $diag.ENDPOINT))
[void]$sb.AppendLine(("TUNNEL_UP={0} SOCKS_LIVE={1} HTTP_LIVE={2}" -f $diag.TUNNEL_UP, $diag.SOCKS_LIVE, $diag.HTTP_LIVE))
[void]$sb.AppendLine(("SETTINGS={0}" -f $settingsProxy))
[void]$sb.AppendLine(("SYSTEM_PROXY={0}" -f (Get-SystemProxyServer)))

$human = $sb.ToString()
$human | Out-File -FilePath (Join-Path $PSScriptRoot 'last-health-check.txt') -Encoding UTF8 -Force

Write-Output ''
Write-Output '--- HEALTH REPORT ---'
Write-Output $human
Write-Output ("HEALTH_EXIT={0}" -f [int]($issues.Count -gt 0))

if (-not $Quiet) {
    Write-Host $human
}

if ($Json) {
    @{
        version = $ver
        issueCount = $issues.Count
        issues = $issues
        fixes = $fixes
        ok = $oks
        report = $human
    } | ConvertTo-Json -Depth 4
}

exit [int]($issues.Count -gt 0)
