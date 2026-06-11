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
