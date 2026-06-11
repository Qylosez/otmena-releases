#Requires -Version 3.0
# Obshie funkcii Otmena (podklyuchaj: . .\otmena-common.ps1)

. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

function Get-GithubRepoName([string]$Repo) {
    $r = $Repo.Trim().TrimEnd('/')
    if ($r -match 'github\.com[:/](.+?)(?:\.git)?/?$') { return $matches[1] }
    return $r
}

function Get-OtmenaUpdateConfig([string]$ConfigFile) {
    if (-not (Test-OtmenaPath $ConfigFile)) { return $null }
    try { return Get-Content $ConfigFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-OtmenaPackageUrl {
    param([string]$ConfigFile = (Join-Path $PSScriptRoot 'update-config.json'))

    $config = Get-OtmenaUpdateConfig $ConfigFile
    if (-not $config) { return $null }

    $packageFile = if ($config.packageFile) { [string]$config.packageFile } else { 'Otmena-update.zip' }

    if ($config.githubRepo) {
        $repo = Get-GithubRepoName ([string]$config.githubRepo)
        return "https://github.com/$repo/releases/latest/download/$packageFile"
    }

    if ($config.baseUrl) {
        $base = [string]$config.baseUrl.TrimEnd('\', '/')
        if ($base -match '^https?://') { return "$base/$packageFile" }
        return Join-Path $base $packageFile
    }
    return $null
}

function Get-OtmenaPreserveRelativePaths {
    return @(
        'utils\work_mode.enabled',
        'utils\gui.settings',
        'utils\first_run.done',
        'utils\corp_tg_hint.done',
        'utils\portable.flag',
        'utils\telegram-mtproto.json',
        'telegram-vless\config.json',
        'telegram-vless\bin\xray.exe',
        'telegram-vless\bin\xray-windows-64.zip',
        'telegram-vless\bin\xray-bundle.zip',
        'lists\list-general-user.txt',
        'lists\list-exclude-user.txt',
        'lists\ipset-exclude-user.txt'
    )
}

function Copy-OtmenaFile([string]$Src, [string]$Dst) {
    if (-not (Test-OtmenaPath $Src)) { return $false }
    $parent = Split-Path $Dst -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -Path $Src -Destination $Dst -Force
    return $true
}

function Test-PowerShellOk {
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        return @{ Ok = $false; Message = 'Need PowerShell 3+ (current: ' + $PSVersionTable.PSVersion + ')' }
    }
    return @{ Ok = $true; Message = $PSVersionTable.PSVersion.ToString() }
}

function Get-OtmenaAppVersion {
    $f = Join-Path $PSScriptRoot 'app.version'
    if (Test-OtmenaPath $f) {
        $v = (Get-Content $f -Raw).Trim()
        if ($v) { return $v }
    }
    return 'unknown'
}
