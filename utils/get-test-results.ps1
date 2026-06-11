#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'launcher.ps1')

$report = Test-AllMethods -LeaveBestRunning

foreach ($r in $report.Results) {
    $detail = ($r.Detail -replace '\|', '/')
    Write-Output ("RESULT={0}|{1}|{2}|{3}" -f $r.Group, $r.Name, [int]$r.Success, $detail)
}

if ($report.BestZapret) { Write-Output ("BEST_ZAPRET={0}" -f $report.BestZapret) }
if ($report.BestTelegram) { Write-Output ("BEST_TG={0}" -f $report.BestTelegram) }

$exitCode = if ($report.BestZapret -or $report.BestTelegram) { 0 } else { 1 }
Write-Output ("EXIT={0}" -f $exitCode)
exit $exitCode
