#Requires -Version 3.0
param(
    [string]$PackageUrl,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configFile = Join-Path $PSScriptRoot 'update-config.json'
$exePath = Join-Path $rootDir 'Otmena.exe'

function Write-Step([string]$msg) {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
    Write-Output ("LOG={0}" -f $msg)
}

function Get-PackageSource {
    param([string]$Url)

    if ($Url) { return $Url }

    $fromConfig = Get-OtmenaPackageUrl -ConfigFile $configFile
    if ($fromConfig) { return $fromConfig }

    throw 'Ukazhi PackageUrl ili githubRepo v utils\update-config.json'
}

function Save-PreserveFiles([string]$backupDir) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($rel in (Get-OtmenaPreserveRelativePaths)) {
        $src = Join-Path $rootDir $rel
        if (Test-OtmenaPath $src) {
            $dst = Join-Path $backupDir $rel
            Copy-OtmenaFile $src $dst | Out-Null
        }
    }
}

function Restore-PreserveFiles([string]$backupDir) {
    if (-not (Test-OtmenaPath $backupDir)) { return }
    Get-ChildItem -Path $backupDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($backupDir.Length).TrimStart('\')
        $dst = Join-Path $rootDir $rel
        Copy-OtmenaFile $_.FullName $dst | Out-Null
    }
}

try {
    Write-Step 'Ostanovka zapret...'
    & (Join-Path $PSScriptRoot 'launcher.ps1') -Action stop -Quiet | Out-Null

    $source = Get-PackageSource -Url $PackageUrl
    Write-Step "Istochnik: $source"

    $tempRoot = Join-Path $env:TEMP ("zapret-update-" + [guid]::NewGuid().ToString())
    $zipPath = Join-Path $tempRoot 'package.zip'
    $extractDir = Join-Path $tempRoot 'extract'
    $backupDir = Join-Path $tempRoot 'preserve'
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    Save-PreserveFiles -backupDir $backupDir

    if ($source -match '^https?://') {
        Write-Step 'Skachivanie obnovleniya...'
        Invoke-WebRequest -Uri $source -OutFile $zipPath -UseBasicParsing -TimeoutSec 300
    } else {
        if (-not (Test-OtmenaPath $source)) {
            throw "paket ne naiden: $source"
        }
        Copy-OtmenaFile $source $zipPath | Out-Null
    }

    Write-Step 'Raspakovka...'
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $payload = $extractDir
    $nested = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if ((Get-ChildItem -Path $extractDir -File).Count -eq 0 -and $nested) {
        $payload = $nested.FullName
    }

    $helper = Join-Path $tempRoot 'apply-helper.ps1'
    $escapedRoot = $rootDir.Replace("'", "''")
    $escapedPayload = $payload.Replace("'", "''")
    $escapedBackup = $backupDir.Replace("'", "''")
    $escapedExe = $exePath.Replace("'", "''")

    @"
`$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds 2
Get-Process -Name Otmena,Zapret -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

function Copy-Tree([string]`$src, [string]`$dst) {
    Get-ChildItem -Path `$src -Force | ForEach-Object {
        `$target = Join-Path `$dst `$_.Name
        if (`$_.PSIsContainer) {
            if (-not (Test-Path `$target)) { New-Item -ItemType Directory -Path `$target -Force | Out-Null }
            Copy-Tree `$_.FullName `$target
        } else {
            Copy-Item -Path `$_.FullName -Destination `$target -Force
        }
    }
}

Copy-Tree '$escapedPayload' '$escapedRoot'

`$oldExe = Join-Path '$escapedRoot' 'Zapret.exe'
if (Test-Path `$oldExe) { Remove-Item -Path `$oldExe -Force -ErrorAction SilentlyContinue }

if (Test-Path '$escapedBackup') {
    Get-ChildItem -Path '$escapedBackup' -Recurse -File | ForEach-Object {
        `$rel = `$_.FullName.Substring('$escapedBackup'.Length).TrimStart('\')
        `$dst = Join-Path '$escapedRoot' `$rel
        `$parent = Split-Path `$dst -Parent
        if (-not (Test-Path `$parent)) { New-Item -ItemType Directory -Path `$parent -Force | Out-Null }
        Copy-Item -Path `$_.FullName -Destination `$dst -Force
    }
}

if (Test-Path '$escapedExe') {
    Start-Process -FilePath '$escapedExe'
}

Start-Sleep -Seconds 3
Remove-Item -Path '$($tempRoot.Replace("'", "''"))' -Recurse -Force
"@ | Out-File -FilePath $helper -Encoding UTF8

    Write-Step 'Zapusk ustanovki (Otmena zakroetsya)...'
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$helper`""
    ) -WindowStyle Hidden | Out-Null

    Write-Output 'STATUS=scheduled'
    exit 0
} catch {
    Write-Output 'STATUS=error'
    Write-Output ("ERROR={0}" -f $_.Exception.Message)
    if (-not $Quiet) {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    exit 1
}
