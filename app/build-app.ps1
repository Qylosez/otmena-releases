#Requires -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$outExe = Join-Path $root 'Otmena.exe'
$src = Join-Path $PSScriptRoot 'ZapretApp.cs'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path $csc)) {
    throw "csc.exe not found"
}

$ico = Join-Path $PSScriptRoot 'otmena.ico'
$png = Join-Path $PSScriptRoot 'otmena.png'
if (-not (Test-Path $ico) -or ((Test-Path $png) -and (Get-Item $png).LastWriteTime -gt (Get-Item $ico).LastWriteTime)) {
    & (Join-Path $PSScriptRoot 'make-icon.ps1')
}

& $csc /nologo /target:winexe /optimize+ `
    "/out:$outExe" `
    "/win32icon:$ico" `
    /reference:System.dll `
    /reference:System.Drawing.dll `
    /reference:System.Windows.Forms.dll `
    $src

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Built: $outExe"
