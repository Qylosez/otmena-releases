#Requires -Version 3.0
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configFile = Join-Path $PSScriptRoot 'update-config.json'
$appVersionFile = Join-Path $PSScriptRoot 'app.version'

function Get-LocalVersion {
    if (Test-Path $appVersionFile) {
        $v = (Get-Content $appVersionFile -Raw).Trim()
        if ($v) { return $v }
    }
    $serviceBat = Join-Path $rootDir 'scripts\service.bat'
    if (Test-Path $serviceBat) {
        $m = Select-String -Path $serviceBat -Pattern 'LOCAL_VERSION=([^\r\n]+)' | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim('"') }
    }
    return '0.0.0'
}

function Get-UpdateConfig {
    if (-not (Test-Path $configFile)) { return $null }
    try { return Get-Content $configFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Read-RemoteVersion([string]$baseUrl, [string]$versionFile) {
    $baseUrl = $baseUrl.TrimEnd('\', '/')
    $path = if ($baseUrl -match '^https?://') {
        "$baseUrl/$versionFile"
    } else {
        Join-Path $baseUrl $versionFile
    }

    if ($path -match '^https?://') {
        return (Invoke-WebRequest -Uri $path -UseBasicParsing -TimeoutSec 12 -Headers @{ 'Cache-Control' = 'no-cache' }).Content.Trim()
    }
    if (-not (Test-Path -Path $path)) {
        throw "version file not found: $path"
    }
    return (Get-Content -Path $path -Raw).Trim()
}

function Get-GithubReleaseInfo {
    param(
        [string]$Repo,
        [string]$PackageFile,
        [string]$Token
    )

    $repo = $Repo.Trim().TrimEnd('/')
    if ($repo -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
        $repo = $matches[1]
    }

    $headers = @{
        'User-Agent' = 'Otmena-Updater'
        'Accept'     = 'application/vnd.github+json'
    }
    if ($Token) {
        $headers['Authorization'] = "Bearer $Token"
    }

    $apiError = $null
    $url = "https://api.github.com/repos/$repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 15
        $remoteVersion = ([string]$release.tag_name).Trim() -replace '^v', ''
        if (-not $remoteVersion) {
            throw 'empty release tag'
        }

        $asset = $release.assets | Where-Object { $_.name -eq $PackageFile } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
        }
        if (-not $asset) {
            throw "asset not found: $PackageFile"
        }

        return @{
            Version    = $remoteVersion
            PackageUrl = [string]$asset.browser_download_url
            Method     = 'api'
        }
    } catch {
        $apiError = $_.Exception.Message
    }

    $verUrl = "https://github.com/$repo/releases/latest/download/version.txt"
    $pkgUrl = "https://github.com/$repo/releases/latest/download/$PackageFile"
    try {
        $remoteVersion = (Invoke-WebRequest -Uri $verUrl -UseBasicParsing -TimeoutSec 15 -Headers @{ 'Cache-Control' = 'no-cache' }).Content.Trim()
        if (-not $remoteVersion) { throw 'empty version.txt' }
        return @{
            Version    = ($remoteVersion -replace '^v', '')
            PackageUrl = $pkgUrl
            Method     = 'direct'
        }
    } catch {
        $directError = $_.Exception.Message
        if ($apiError) {
            throw "API: $apiError | direct: $directError"
        }
        throw $directError
    }
}

$localVersion = Get-LocalVersion
Write-Output ("VERSION_LOCAL={0}" -f $localVersion)

$config = Get-UpdateConfig
$packageFile = if ($config.packageFile) { [string]$config.packageFile } else { 'Otmena-update.zip' }

if (-not $config) {
    Write-Output 'UPDATE_ERROR=net fajla utils\update-config.json'
    Write-Output 'VERSION_REMOTE='
    Write-Output 'UPDATE_AVAILABLE=0'
    exit 1
}

if (-not $config.enabled) {
    Write-Output 'UPDATE_ERROR=obnovleniya vyklyucheny v config'
    Write-Output 'VERSION_REMOTE='
    Write-Output 'UPDATE_AVAILABLE=0'
    exit 1
}

if ($config.githubRepo) {
    try {
        $token = if ($config.githubToken) { [string]$config.githubToken } else { '' }
        $info = Get-GithubReleaseInfo -Repo ([string]$config.githubRepo) -PackageFile $packageFile -Token $token
        Write-Output ("VERSION_REMOTE={0}" -f $info.Version)
        Write-Output 'UPDATE_SOURCE=github'
        $update = [int]($info.Version -and ($info.Version -ne $localVersion))
        Write-Output ("UPDATE_AVAILABLE={0}" -f $update)
        Write-Output ("PACKAGE_URL={0}" -f $info.PackageUrl)
        Write-Output ("UPDATE_METHOD={0}" -f $info.Method)
        if (-not $Quiet) {
            if ($update) {
                Write-Host ("GitHub: update " + $info.Version + " (local " + $localVersion + ")") -ForegroundColor Yellow
            } else {
                Write-Host ("GitHub: OK " + $localVersion) -ForegroundColor Green
            }
        }
        exit 0
    } catch {
        Write-Output 'VERSION_REMOTE='
        Write-Output 'UPDATE_AVAILABLE=0'
        Write-Output ("UPDATE_ERROR={0}" -f $_.Exception.Message)
        if (-not $Quiet) {
            Write-Host ("GitHub error: " + $_.Exception.Message) -ForegroundColor Yellow
        }
        exit 1
    }
}

if ($config.baseUrl) {
    $baseUrl = [string]$config.baseUrl
    $versionFile = if ($config.versionFile) { [string]$config.versionFile } else { 'version.txt' }

    try {
        $remote = Read-RemoteVersion -baseUrl $baseUrl -VersionFile $versionFile
        Write-Output ("VERSION_REMOTE={0}" -f $remote)
        Write-Output 'UPDATE_SOURCE=custom'
        $update = [int]($remote -and ($remote -ne $localVersion))
        Write-Output ("UPDATE_AVAILABLE={0}" -f $update)

        $packageUrl = if ($baseUrl -match '^https?://') {
            "$($baseUrl.TrimEnd('/'))/$packageFile"
        } else {
            Join-Path $baseUrl $packageFile
        }
        Write-Output ("PACKAGE_URL={0}" -f $packageUrl)
        exit 0
    } catch {
        Write-Output 'VERSION_REMOTE='
        Write-Output 'UPDATE_AVAILABLE=0'
        Write-Output ("UPDATE_ERROR={0}" -f $_.Exception.Message)
        exit 1
    }
}

Write-Output 'UPDATE_ERROR=ukazhi githubRepo v update-config.json'
Write-Output 'VERSION_REMOTE='
Write-Output 'UPDATE_AVAILABLE=0'
exit 1
