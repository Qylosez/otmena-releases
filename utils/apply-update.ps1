#Requires -Version 3.0
param(
    [string]$PackageUrl,
    [switch]$Quiet,
    [switch]$InPlace
)

$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'otmena-common.ps1')

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configFile = Join-Path $PSScriptRoot 'update-config.json'
$exePath = Join-Path $rootDir 'Otmena.exe'
$logFile = Join-Path $PSScriptRoot 'update.log'

function Write-UpdateLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, $utf8)
    } catch {}
    Write-Output ("LOG={0}" -f $msg)
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
}

function Write-UpdateErr([string]$msg) {
    Write-UpdateLog "ERROR: $msg"
    Write-Output ("ERROR={0}" -f $msg)
}

function Get-PackageSource {
    param([string]$Url)
    if ($Url -and $Url -notmatch '^https?://') { return $Url }
    if ($Url -match 'https?://github\.com/' -and $Url -notmatch 'gh-proxy\.com') {
        Write-UpdateLog 'Rewrite GitHub URL via gh-proxy.com'
        return ('https://gh-proxy.com/' + $Url)
    }
    if ($Url) { return $Url }
    $localZip = Join-Path $rootDir 'Otmena-update.zip'
    if (Test-OtmenaZipFile -Path $localZip -MinBytes 200000) {
        Write-UpdateLog "Local zip: $localZip"
        return $localZip
    }
    $fromConfig = Get-OtmenaPackageUrl -ConfigFile $configFile
    if ($fromConfig) { return $fromConfig }
    throw 'Net URL i net Otmena-update.zip v papke. Skachaj zip s GitHub Releases v papku Otmena.'
}

function Save-Package([string]$source, [string]$zipPath) {
    $localZip = Join-Path $rootDir 'Otmena-update.zip'
    if ($source -notmatch '^https?://') {
        if (-not (Test-OtmenaPath $source)) { throw "Paket ne naiden: $source" }
        Copy-OtmenaFile $source $zipPath | Out-Null
        if (-not (Test-OtmenaZipFile -Path $zipPath -MinBytes 200000)) {
            throw "Lokalnyj zip povrezhden. Skachaj Otmena-update.zip zanovo."
        }
        return
    }

    Write-UpdateLog "Download: $source"
    $ok = $false
    $lastErr = ''

    try {
        Save-OtmenaUrl -Url $source -OutFile $zipPath -TimeoutSec 300 -MinBytes 200000
        $ok = $true
    } catch {
        $lastErr = $_.Exception.Message
        Write-UpdateLog "Download fail: $lastErr"
    }

    if (-not $ok -and (Test-OtmenaZipFile -Path $localZip -MinBytes 200000)) {
        Write-UpdateLog "Fallback to local zip: $localZip"
        Copy-OtmenaFile $localZip $zipPath | Out-Null
        $ok = $true
    }

    if (-not $ok) {
        throw "Ne udalos skachat obnovlenie. $lastErr. Polozhi Otmena-update.zip ryadom s Otmena.exe i zapusti UPDATE-MANUAL.bat"
    }
}

function Expand-Zip([string]$zipPath, [string]$dest) {
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $dest -Force
        return
    } catch {
        Write-UpdateLog "Expand-Archive fail: $($_.Exception.Message), try .NET..."
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $dest)
}

function Copy-TreeSafe([string]$src, [string]$dst) {
    Get-ChildItem -Path $src -Force | ForEach-Object {
        $target = Join-Path $dst $_.Name
        if ($_.PSIsContainer) {
            if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
            Copy-TreeSafe $_.FullName $target
        } else {
            for ($try = 0; $try -lt 5; $try++) {
                try {
                    Copy-Item -Path $_.FullName -Destination $target -Force -ErrorAction Stop
                    break
                } catch {
                    Start-Sleep -Milliseconds (300 * ($try + 1))
                    if ($try -eq 4) { throw "Copy fail: $target — $($_.Exception.Message)" }
                }
            }
        }
    }
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
    Write-UpdateLog '=== update start ==='

    $source = Get-PackageSource -Url $PackageUrl
    $tempRoot = Join-Path $env:TEMP ("otmena-update-" + [guid]::NewGuid().ToString())
    $zipPath = Join-Path $tempRoot 'package.zip'
    $extractDir = Join-Path $tempRoot 'extract'
    $backupDir = Join-Path $tempRoot 'preserve'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    Save-PreserveFiles -backupDir $backupDir
    # Download WHILE xray is still up (GitHub is often blocked without the tunnel).
    Save-Package -source $source -zipPath $zipPath

    Get-Process -Name winws, xray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    taskkill /IM winws.exe /F 2>$null | Out-Null
    taskkill /IM xray.exe /F 2>$null | Out-Null

    Write-UpdateLog 'Unpack...'
    Expand-Zip -zipPath $zipPath -dest $extractDir

    $payload = $extractDir
    $nested = Get-ChildItem -Path $extractDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ((Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue).Count -eq 0 -and $nested) {
        $payload = $nested.FullName
    }

    $exeInZip = Get-ChildItem -Path $payload -Filter 'Otmena.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exeInZip) {
        Write-UpdateLog 'WARN: v arhive net Otmena.exe — obnovlyayu tolko skripty'
    }

    if ($InPlace -or -not $exeInZip) {
        Write-UpdateLog 'In-place copy...'
        Copy-TreeSafe $payload $rootDir
        Restore-PreserveFiles -backupDir $backupDir
        & (Join-Path $PSScriptRoot 'sync-service-args.ps1') 2>$null | Out-Null
        $verSrc = Join-Path $payload 'utils\app.version'
        if (Test-Path $verSrc) { Copy-Item $verSrc (Join-Path $PSScriptRoot 'app.version') -Force }
        Write-UpdateLog '=== update ok (in-place) ==='
        Write-Output 'STATUS=ok'
        exit 0
    }

    $helper = Join-Path $tempRoot 'apply-helper.ps1'
    $escapedRoot = $rootDir.Replace("'", "''")
    $escapedPayload = $payload.Replace("'", "''")
    $escapedBackup = $backupDir.Replace("'", "''")
    $escapedExe = $exePath.Replace("'", "''")
    $escapedTemp = $tempRoot.Replace("'", "''")

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
            for (`$t = 0; `$t -lt 5; `$t++) {
                try { Copy-Item -Path `$_.FullName -Destination `$target -Force -ErrorAction Stop; break }
                catch { Start-Sleep -Milliseconds 500 }
            }
        }
    }
}

Copy-Tree '$escapedPayload' '$escapedRoot'
`$oldExe = Join-Path '$escapedRoot' 'Zapret.exe'
if (Test-Path `$oldExe) { Remove-Item `$oldExe -Force -ErrorAction SilentlyContinue }

if (Test-Path '$escapedBackup') {
    Get-ChildItem -Path '$escapedBackup' -Recurse -File | ForEach-Object {
        `$rel = `$_.FullName.Substring('$escapedBackup'.Length).TrimStart('\')
        `$dst = Join-Path '$escapedRoot' `$rel
        `$parent = Split-Path `$dst -Parent
        if (-not (Test-Path `$parent)) { New-Item -ItemType Directory -Path `$parent -Force | Out-Null }
        Copy-Item -Path `$_.FullName -Destination `$dst -Force -ErrorAction SilentlyContinue
    }
}

try {
    `$sync = Join-Path '$escapedRoot' 'utils\sync-service-args.ps1'
    if (Test-Path `$sync) { & `$sync 2>`$null | Out-Null }
} catch {}

if (Test-Path '$escapedExe') { Start-Process -FilePath '$escapedExe' }
Start-Sleep -Seconds 2
Remove-Item -Path '$escapedTemp' -Recurse -Force -ErrorAction SilentlyContinue
"@ | Out-File -FilePath $helper -Encoding UTF8

    Write-UpdateLog 'Scheduled restart install...'
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$helper`""
    ) -WindowStyle Hidden | Out-Null

    Write-Output 'STATUS=scheduled'
    Write-UpdateLog '=== update scheduled ==='
    exit 0
} catch {
    Write-UpdateErr $_.Exception.Message
    if (-not $Quiet) { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    exit 1
}
