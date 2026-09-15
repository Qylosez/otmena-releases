#Requires -Version 3.0
param(
    [switch]$Quiet,
    [switch]$FromGui,
    [string]$RootDir
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $here 'otmena-common.ps1')

function Write-BootLog([string]$msg) {
    Write-Output ("LOG={0}" -f $msg)
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
}

function Resolve-OtmenaRoot {
    if ($RootDir -and (Test-Path (Join-Path $RootDir 'Otmena.exe'))) { return (Resolve-Path $RootDir).Path }
    $fromUtils = (Resolve-Path (Join-Path $here '..')).Path
    if (Test-Path (Join-Path $fromUtils 'Otmena.exe')) { return $fromUtils }
    $proc = Get-Process -Name Otmena -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        $d = Split-Path $proc.Path -Parent
        if (Test-Path (Join-Path $d 'Otmena.exe')) { return $d }
    }
    foreach ($d in @(
        (Join-Path $env:USERPROFILE 'Desktop\Otmena'),
        (Join-Path $env:USERPROFILE 'Documents\Otmena'),
        'C:\Otmena',
        'D:\Otmena'
    )) {
        if (Test-Path (Join-Path $d 'Otmena.exe')) { return $d }
    }
    throw 'Ne nashla papku Otmena. Zapusti Otmena.exe i povtori, ili polozhi etot skript v papku s Otmena.exe.'
}

try {
    Write-BootLog '=== bootstrap update ==='
    $root = Resolve-OtmenaRoot
    Write-BootLog "Root: $root"
    $zip = Join-Path $root 'Otmena-update.zip'
    $url = 'https://github.com/Qylosez/otmena-releases/releases/latest/download/Otmena-update.zip'
    Write-BootLog 'Download zip (mirrors, then tunnel)...'
    Save-OtmenaUrl -Url $url -OutFile $zip -TimeoutSec 60 -MinBytes 200000
    if (-not (Test-OtmenaZipFile -Path $zip -MinBytes 200000)) {
        throw 'Zip povrezhden posle skachivaniya'
    }
    Write-BootLog ("Zip OK, {0} bytes" -f (Get-Item $zip).Length)

    $apply = Join-Path $root 'utils\apply-update.ps1'
    if (-not (Test-Path $apply)) { throw "Net $apply" }

    if ($FromGui) {
        # Local zip is ready; apply-update without PackageUrl will use it.
        Write-BootLog 'Apply from local zip...'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply -Quiet
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            Write-Output 'STATUS=scheduled'
            Write-BootLog '=== bootstrap ok ==='
            exit 0
        }
        throw "apply-update exit $code"
    }

    Get-Process -Name Otmena, Zapret -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-BootLog 'Apply in-place...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply -InPlace -Quiet
    if ($LASTEXITCODE -ne 0) { throw "apply-update exit $LASTEXITCODE" }
    $exe = Join-Path $root 'Otmena.exe'
    if (Test-Path $exe) { Start-Process -FilePath $exe }
    Write-Output 'STATUS=ok'
    Write-BootLog '=== bootstrap ok ==='
    exit 0
} catch {
    Write-Output ("ERROR={0}" -f $_.Exception.Message)
    Write-Output ("LOG=ERROR: {0}" -f $_.Exception.Message)
    if (-not $Quiet) { Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red }
    exit 1
}
