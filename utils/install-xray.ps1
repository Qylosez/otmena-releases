#Requires -Version 3.0
param(
    [switch]$Quiet,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utilsDir = $PSScriptRoot
$rootDir = Split-Path $utilsDir -Parent
$binDir = Join-Path $rootDir 'telegram-vless\bin'
$xrayExe = Join-Path $binDir 'xray.exe'
$readmePath = Join-Path $binDir 'README-xray.txt'

function Write-Step([string]$msg, [string]$color) {
    if (-not $Quiet) {
        if ($color) { Write-Host $msg -ForegroundColor $color }
        else { Write-Host $msg }
    }
}

function Get-UpdateRepo {
    $configFile = Join-Path $utilsDir 'update-config.json'
    if (-not (Test-Path $configFile)) { return 'Qylosez/otmena-releases' }
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($cfg.githubRepo) { return [string]$cfg.githubRepo.Trim() }
    } catch {}
    return 'Qylosez/otmena-releases'
}

function Get-XrayZipName {
    $configFile = Join-Path $utilsDir 'update-config.json'
    if (-not (Test-Path $configFile)) { return 'xray-windows-64.zip' }
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($cfg.xrayZipFile) { return [string]$cfg.xrayZipFile }
    } catch {}
    return 'xray-windows-64.zip'
}

function Expand-XrayZip([string]$zipPath) {
    $extractDir = Join-Path $env:TEMP ('xray-extract-' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $found = Get-ChildItem -Path $extractDir -Filter 'xray.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw 'xray.exe not in archive' }
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item -Path $found.FullName -Destination $xrayExe -Force
    } finally {
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
}

function Install-FromZipFile([string]$zipPath, [string]$label) {
    if (-not (Test-Path $zipPath)) { return $false }
    Write-Step "xray: $label (local zip)..." Cyan
    try {
        Expand-XrayZip $zipPath
        return $true
    } catch {
        Write-Step ("xray: $label failed - " + $_.Exception.Message) Yellow
        return $false
    }
}

function Install-FromUrl([string]$url, [string]$label) {
    if ([string]::IsNullOrWhiteSpace($url)) { return $false }
    Write-Step "xray: $label..." Cyan
    $zipPath = Join-Path $env:TEMP ('xray-dl-' + [guid]::NewGuid().ToString() + '.zip')
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 180
        if ((Get-Item $zipPath).Length -lt 1000000) {
            throw 'file too small (not a zip?)'
        }
        Expand-XrayZip $zipPath
        return $true
    } catch {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Write-Step ("xray: $label - " + $_.Exception.Message) Yellow
        return $false
    }
}

function Install-FromGithubApi {
    Write-Step 'xray: GitHub API (XTLS/Xray-core)...' Cyan
    try {
        $api = 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'
        $release = Invoke-RestMethod -Uri $api -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'Otmena-Installer' }
        $asset = $release.assets | Where-Object { $_.name -match 'windows-64\.zip$' } | Select-Object -First 1
        if (-not $asset) { throw 'windows-64.zip not found' }
        return Install-FromUrl $asset.browser_download_url 'XTLS API'
    } catch {
        Write-Step ("xray: GitHub API - " + $_.Exception.Message) Yellow
        return $false
    }
}

if ((Test-Path $xrayExe) -and -not $Force) {
    Write-Step "xray OK: $xrayExe" Green
    exit 0
}

New-Item -ItemType Directory -Path $binDir -Force | Out-Null

$repo = Get-UpdateRepo
$zipName = Get-XrayZipName
$localZips = @(
    (Join-Path $binDir $zipName),
    (Join-Path $binDir 'xray-bundle.zip'),
    (Join-Path $binDir 'Xray-windows-64.zip')
)

foreach ($lz in $localZips) {
    if (Install-FromZipFile $lz "local $($lz | Split-Path -Leaf)") {
        Write-Step "xray installed: $xrayExe" Green
        exit 0
    }
}

$urls = @(
    @{ Url = "https://github.com/$repo/releases/latest/download/$zipName"; Label = "Otmena releases ($zipName)" },
    @{ Url = 'https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip'; Label = 'XTLS direct' },
    @{ Url = 'https://github.com/XTLS/Xray-core/releases/latest/download/xray-windows-64.zip'; Label = 'XTLS direct alt' }
)

foreach ($u in $urls) {
    if (Install-FromUrl $u.Url $u.Label) {
        Write-Step "xray installed: $xrayExe" Green
        exit 0
    }
}

if (Install-FromGithubApi) {
    Write-Step "xray installed: $xrayExe" Green
    exit 0
}

$offlineMsg = @"
xray.exe not installed.

Automatic download failed (GitHub may be blocked).
1. On another PC download: $zipName from https://github.com/$repo/releases
   or Xray-windows-64.zip from https://github.com/XTLS/Xray-core/releases
2. Put the zip into: $binDir
3. Start Otmena again (it will unpack automatically).

Or put xray.exe directly into: $binDir
"@

@($offlineMsg) | Out-File -FilePath $readmePath -Encoding UTF8
Write-Step $offlineMsg Yellow
exit 2
