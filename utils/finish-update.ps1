#Requires -Version 3.0
# Runs once after a zip copy. Deletes files left by the original Otmena.
$ErrorActionPreference = 'SilentlyContinue'

$utils = $PSScriptRoot
$root = (Resolve-Path (Join-Path $utils '..')).Path.TrimEnd('\')
$pending = Join-Path $utils 'update-clean.pending'
$manifestPath = Join-Path $utils 'payload-manifest.txt'

if (-not (Test-Path -LiteralPath $pending)) { exit 0 }
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue
    exit 0
}

$wanted = @{}
Get-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
    $n = ([string]$_).Trim().ToLowerInvariant().Replace('/', '\')
    if ($n) { $wanted[$n] = $true }
}

function Test-KeepRel([string]$rel) {
    $n = $rel.ToLowerInvariant()
    if ($n -eq 'otmena-update.zip') { return $true }
    if ($n -match '\.(log|pid|lock)$') { return $true }
    foreach ($p in @(
        'utils\work_mode.enabled',
        'utils\gui.settings',
        'utils\first_run.done',
        'utils\corp_tg_hint.done',
        'utils\portable.flag',
        'utils\telegram-mtproto.json',
        'telegram-vless\subscription.json',
        'telegram-vless\bin\xray.exe',
        'telegram-vless\bin\xray-windows-64.zip',
        'telegram-vless\bin\xray-bundle.zip',
        'lists\list-general-user.txt',
        'lists\list-exclude-user.txt',
        'lists\ipset-exclude-user.txt'
    )) {
        if ($n -eq $p) { return $true }
        if ($n.StartsWith($p + '\')) { return $true }
    }
    return $false
}

function Get-Rel([string]$full) {
    if ($full.Length -le $root.Length) { return '' }
    return $full.Substring($root.Length).TrimStart('\')
}

$removed = 0
Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = Get-Rel $_.FullName
    if (-not $rel) { return }
    $key = $rel.ToLowerInvariant()
    if ($wanted.ContainsKey($key)) { return }
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

Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
        $rel = Get-Rel $_.FullName
        if ($rel -and (Test-KeepRel $rel)) { return }
        $kids = @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)
        if ($kids.Count -eq 0) {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
            } catch {}
        }
    }

Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue
Write-Output ("STALE_REMOVED={0}" -f $removed)
exit 0
