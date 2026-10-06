#Requires -Version 3.0
# After a zip update, delete leftover files from older Otmena/zapret installs.
param(
    [Parameter(Mandatory)][string]$PayloadDir,
    [Parameter(Mandatory)][string]$RootDir
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$payload = (Resolve-Path -LiteralPath $PayloadDir).Path
$root = (Resolve-Path -LiteralPath $RootDir).Path

function Get-Rel([string]$base, [string]$full) {
    return $full.Substring($base.Length).TrimStart('\', '/')
}

function Test-KeepRel([string]$rel) {
    if ([string]::IsNullOrWhiteSpace($rel)) { return $true }
    $n = $rel.ToLowerInvariant()
    if ($n -eq 'otmena-update.zip') { return $true }
    if ($n -match '\.(log|pid|lock)$') { return $true }
    if ($n -eq 'utils\update.log' -or $n -eq 'utils/update.log') { return $true }
    foreach ($p in (Get-OtmenaPreserveRelativePaths)) {
        $pl = $p.ToLowerInvariant()
        if ($n -eq $pl) { return $true }
        if ($n.StartsWith($pl + '\') -or $n.StartsWith($pl + '/')) { return $true }
    }
    return $false
}

$wanted = @{}
Get-ChildItem -LiteralPath $payload -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $wanted[(Get-Rel $payload $_.FullName)] = $true
}

$removed = 0
Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = Get-Rel $root $_.FullName
    if ($wanted.ContainsKey($rel)) { return }
    if (Test-KeepRel $rel) { return }
    try {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
        $removed++
    } catch {}
}

$oldExe = Join-Path $root 'Zapret.exe'
if (Test-Path -LiteralPath $oldExe) {
    Remove-Item -LiteralPath $oldExe -Force -ErrorAction SilentlyContinue
    $removed++
}

Write-Output ("STALE_REMOVED={0}" -f $removed)
exit 0
