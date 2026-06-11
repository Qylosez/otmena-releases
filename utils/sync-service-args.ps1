#Requires -Version 3.0
# Regenerates utils\alt11-service-args.txt from general (ALT11).bat with correct absolute paths.
$ErrorActionPreference = 'Stop'

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$alt11Bat = Join-Path $rootDir 'scripts\general (ALT11).bat'
$outFile = Join-Path $PSScriptRoot 'alt11-service-args.txt'
$binMarker = '%BIN%winws.exe'

if (-not (Test-Path $alt11Bat)) {
    throw "Missing $alt11Bat"
}

$binDir = Join-Path $rootDir 'bin\'
$listsDir = Join-Path $rootDir 'lists\'

function Get-ShortPath([string]$path) {
    $fso = New-Object -ComObject Scripting.FileSystemObject
    if ($fso.FolderExists($path)) { return $fso.GetFolder($path).ShortPath }
    if ($fso.FileExists($path)) { return $fso.GetFile($path).ShortPath }
    return $path
}

$binDirShort = (Get-ShortPath $binDir).TrimEnd('\') + '\'
$listsDirShort = (Get-ShortPath $listsDir).TrimEnd('\') + '\'
$raw = [System.IO.File]::ReadAllText($alt11Bat)
$segment = ($raw -split [regex]::Escape($binMarker), 2)[1]
if (-not $segment) {
    throw 'Could not find winws.exe arguments in general (ALT11).bat'
}

$segment = $segment -replace '\^[\r\n]+', ' '
$segment = $segment -replace '[\r\n]+', ' '
$segment = $segment.Replace('%BIN%', $binDirShort)
$segment = $segment.Replace('%LISTS%', $listsDirShort)
$segment = $segment.Replace('%GameFilterTCP%', '12')
$segment = $segment.Replace('%GameFilterUDP%', '12')
$segment = $segment -replace '\s+', ' '
$segment = $segment.Trim()
$segment = $segment.TrimStart('"').Trim()

if (-not $segment.StartsWith('--')) {
    throw 'Parsed winws arguments look invalid.'
}

$line = '"' + $segment
[System.IO.File]::WriteAllText($outFile, $line, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $outFile"
