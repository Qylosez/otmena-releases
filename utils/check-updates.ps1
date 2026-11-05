#Requires -Version 3.0
param([switch]$Quiet)

$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}
$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configFile = Join-Path $PSScriptRoot 'update-config.json'
$appVersionFile = Join-Path $PSScriptRoot 'app.version'

function Get-LocalVersion {
    if (Test-Path $appVersionFile) {
        $v = (Get-Content $appVersionFile -Raw).Trim()
        if ($v) { return $v }
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

function Get-GithubOriginUrl([string]$Url) {
    if ($Url -match '^https://gh-proxy\.com/(.+)$') { return $matches[1] }
    if ($Url -match '^https://ghfast\.top/(.+)$') { return $matches[1] }
    if ($Url -match '^https://ghproxy\.net/(.+)$') { return $matches[1] }
    return $Url
}

function Get-MirrorPackageUrl([string]$Url) {
    $origin = Get-GithubOriginUrl $Url
    if ($origin -match 'https?://github\.com/') {
        return 'https://gh-proxy.com/' + $origin
    }
    return $Url
}

function Test-UpdateZip([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt 200000) { return $false }
    $fs = [IO.File]::OpenRead($Path)
    try {
        return ($fs.ReadByte() -eq 0x50 -and $fs.ReadByte() -eq 0x4B -and $fs.ReadByte() -eq 0x03 -and $fs.ReadByte() -eq 0x04)
    } finally { $fs.Close() }
}

function Save-UpdateZipQuick([string]$GithubUrl, [string]$OutFile) {
    $origin = Get-GithubOriginUrl $GithubUrl
    $urls = New-Object System.Collections.Generic.List[string]
    if ($origin -match 'https?://github\.com/') {
        [void]$urls.Add(('https://gh-proxy.com/' + $origin))
    } else {
        [void]$urls.Add($GithubUrl)
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($u in $urls) {
        try {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            if ($curl) {
                & curl.exe -fsSL --connect-timeout 8 --max-time 12 -A Otmena-Updater -o $OutFile $u 2>$null | Out-Null
            } else {
                $req = [Net.HttpWebRequest]::Create($u)
                $req.Method = 'GET'
                $req.UserAgent = 'Otmena-Updater'
                $req.Timeout = 12000
                $req.ReadWriteTimeout = 16000
                $req.AllowAutoRedirect = $true
                $req.Proxy = [Net.GlobalProxySelection]::GetEmptyWebProxy()
                $resp = $req.GetResponse()
                $in = $resp.GetResponseStream()
                $out = [IO.File]::Create($OutFile)
                try {
                    $buf = New-Object byte[] 81920
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n) }
                } finally {
                    $out.Close(); $in.Close(); $resp.Close()
                }
            }
            if (Test-UpdateZip $OutFile) { return $true }
        } catch {}
    }
    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    return $false
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
            $asset = $release.assets | Where-Object {
                $_.name -like '*.zip' -and $_.name -notmatch 'xray' -and $_.name -notmatch 'windows-64'
            } | Select-Object -First 1
        }
        if (-not $asset) {
            throw "asset not found: $PackageFile"
        }

        $pkgUrl = [string]$asset.browser_download_url
        if (-not $pkgUrl) {
            $pkgUrl = "https://github.com/$repo/releases/download/v$remoteVersion/$PackageFile"
        }
        return @{
            Version    = $remoteVersion
            PackageUrl = $pkgUrl
            Method     = 'api'
        }
    } catch {
        $apiError = $_.Exception.Message
    }

    foreach ($verUrl in @(
        "https://gh-proxy.com/https://github.com/$repo/releases/latest/download/version.txt",
        "https://ghfast.top/https://github.com/$repo/releases/latest/download/version.txt",
        "https://github.com/$repo/releases/latest/download/version.txt"
    )) {
        try {
            $remoteVersion = (Invoke-WebRequest -Uri $verUrl -UseBasicParsing -TimeoutSec 10 -Headers @{ 'Cache-Control' = 'no-cache' }).Content.Trim()
            if (-not $remoteVersion) { continue }
            return @{
                Version    = ($remoteVersion -replace '^v', '')
                PackageUrl = "https://github.com/$repo/releases/latest/download/$PackageFile"
                Method     = 'direct'
            }
        } catch {}
    }
    if ($apiError) { throw "API: $apiError | mirrors failed" }
    throw 'version.txt unavailable'
}

function Publish-UpdateInfo {
    param($Info, [string]$PackageFile)
    $localVersion = Get-LocalVersion
    Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
    Write-Output ("VERSION_REMOTE={0}" -f $Info.Version)
    Write-Output 'UPDATE_SOURCE=github'
    $update = [int]($Info.Version -and ($Info.Version -ne $localVersion))
    Write-Output ("UPDATE_AVAILABLE={0}" -f $update)

    $origin = Get-GithubOriginUrl ([string]$Info.PackageUrl)
    $packageUrl = Get-MirrorPackageUrl $origin
    if ($update) {
        $localZip = Join-Path $rootDir $PackageFile
        if (Save-UpdateZipQuick -GithubUrl $origin -OutFile $localZip) {
            $packageUrl = $localZip
            Write-Output 'UPDATE_METHOD=local-zip'
        } else {
            Write-Output ("UPDATE_METHOD={0}" -f $Info.Method)
        }
    } else {
        Write-Output ("UPDATE_METHOD={0}" -f $Info.Method)
    }
    Write-Output ("PACKAGE_URL={0}" -f $packageUrl)
    if (-not $Quiet) {
        if ($update) {
            Write-Host ("GitHub: update " + $Info.Version + " (local " + $localVersion + ")") -ForegroundColor Yellow
        } else {
            Write-Host ("GitHub: OK " + $localVersion) -ForegroundColor Green
        }
    }
}

$localVersion = Get-LocalVersion
$config = Get-UpdateConfig
$packageFile = if ($config.packageFile) { [string]$config.packageFile } else { 'Otmena-update.zip' }

if (-not $config) {
    Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
    Write-Output 'UPDATE_ERROR=net fajla utils\update-config.json'
    Write-Output 'VERSION_REMOTE='
    Write-Output 'UPDATE_AVAILABLE=0'
    exit 1
}

if (-not $config.enabled) {
    Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
    Write-Output 'UPDATE_ERROR=obnovleniya vyklyucheny v config'
    Write-Output 'VERSION_REMOTE='
    Write-Output 'UPDATE_AVAILABLE=0'
    exit 1
}

if ($config.githubRepo) {
    try {
        $token = if ($config.githubToken) { [string]$config.githubToken } else { '' }
        $info = Get-GithubReleaseInfo -Repo ([string]$config.githubRepo) -PackageFile $packageFile -Token $token
        Publish-UpdateInfo -Info $info -PackageFile $packageFile
        exit 0
    } catch {
        Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
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
        Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
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
        Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
        Write-Output 'VERSION_REMOTE='
        Write-Output 'UPDATE_AVAILABLE=0'
        Write-Output ("UPDATE_ERROR={0}" -f $_.Exception.Message)
        exit 1
    }
}

Write-Output ("VERSION_LOCAL={0}" -f $localVersion)
Write-Output 'UPDATE_ERROR=ukazhi githubRepo v update-config.json'
Write-Output 'VERSION_REMOTE='
Write-Output 'UPDATE_AVAILABLE=0'
exit 1
