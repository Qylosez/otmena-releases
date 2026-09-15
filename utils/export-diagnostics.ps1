#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('=== Otmena Diagnostics ===')
[void]$sb.AppendLine(("Date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
[void]$sb.AppendLine(("Folder: {0}" -f $rootDir))
[void]$sb.AppendLine(("AppVersion: {0}" -f (Get-OtmenaAppVersion)))
[void]$sb.AppendLine(("PowerShell: {0}" -f (Test-PowerShellOk).Message))
[void]$sb.AppendLine('')

$healthFile = Join-Path $PSScriptRoot 'last-health-check.txt'
& (Join-Path $PSScriptRoot 'run-health-check.ps1') -Quiet 2>$null | Out-Null
if (Test-Path $healthFile) {
    [void]$sb.AppendLine((Get-Content $healthFile -Raw -ErrorAction SilentlyContinue).Trim())
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('--- Environment ---')
$envLines = & (Join-Path $PSScriptRoot 'detect-environment.ps1')
foreach ($line in $envLines) { [void]$sb.AppendLine($line) }

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Status ---')
$statusLines = & (Join-Path $PSScriptRoot 'get-status.ps1')
foreach ($line in $statusLines) { [void]$sb.AppendLine($line) }

$xrayPath = Join-Path $rootDir 'telegram-vless\bin\xray.exe'
$xrayZip = Join-Path $rootDir 'telegram-vless\bin\xray-windows-64.zip'
if (Test-OtmenaPath $xrayPath) {
    [void]$sb.AppendLine('XRAY_PATH=present')
} elseif (Test-OtmenaPath $xrayZip) {
    [void]$sb.AppendLine('XRAY_PATH=zip ready (restart Otmena to unpack)')
} else {
    [void]$sb.AppendLine('XRAY_PATH=missing (need xray-windows-64.zip on GitHub Releases or internet)')
}

$subFile = Join-Path $rootDir 'telegram-vless\subscription.json'
if (Test-OtmenaPath $subFile) {
    [void]$sb.AppendLine('VLESS_SUB=present (vpn.dance)')
} else {
    [void]$sb.AppendLine('VLESS_SUB=missing')
}
$metaFile = Join-Path $rootDir 'telegram-vless\subscription.meta.json'
if (Test-OtmenaPath $metaFile) {
    [void]$sb.AppendLine(('VLESS_META={0}' -f ((Get-Content $metaFile -Raw).Trim())))
}

. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')
$cursorDiag = Get-CursorTunnelDiagnostics
foreach ($p in $cursorDiag.Keys) {
    [void]$sb.AppendLine(("CURSOR_{0}={1}" -f $p, $cursorDiag[$p]))
}
if ($cursorDiag.SETTINGS_PROXY -and $cursorDiag.PROXY_URL -and ($cursorDiag.SETTINGS_PROXY -ne $cursorDiag.PROXY_URL)) {
    [void]$sb.AppendLine('CURSOR_MISMATCH=1 (zapusti CURSOR-WORK.bat)')
}

$watchLog = Join-Path $PSScriptRoot 'cursor-watch.log'
if (Test-OtmenaPath $watchLog) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('--- cursor-watch.log (last 15 lines) ---')
    Get-Content $watchLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { [void]$sb.AppendLine($_) }
}

$mtprotoScript = Join-Path $PSScriptRoot 'set-telegram-mtproto.ps1'
if (Test-OtmenaPath $mtprotoScript) {
    $c = Get-Content $mtprotoScript -Raw -ErrorAction SilentlyContinue
    if ($c -match 'Start-Process\s+-LiteralPath') {
        [void]$sb.AppendLine('MTProto_SCRIPT=OUTDATED (update utils from release 1.0.8+)')
    } else {
        [void]$sb.AppendLine('MTProto_SCRIPT=ok')
    }
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- launcher.log (last 40 lines) ---')
$logFile = Join-Path $PSScriptRoot 'launcher.log'
if (Test-OtmenaPath $logFile) {
    Get-Content $logFile -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { [void]$sb.AppendLine($_) }
} else {
    [void]$sb.AppendLine('(no log file)')
}

Write-Output $sb.ToString()
