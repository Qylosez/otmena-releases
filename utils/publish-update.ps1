#Requires -Version 3.0
param(
    [string]$PublishPath,
    [string]$GitHubRepo,
    [switch]$Bump,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appVersionFile = Join-Path $PSScriptRoot 'app.version'

if (-not $PublishPath -and -not $GitHubRepo) {
    throw 'Ukazhi -GitHubRepo owner/repo ili -PublishPath'
}

function Get-CurrentVersion {
    if (Test-Path $appVersionFile) {
        return (Get-Content $appVersionFile -Raw).Trim()
    }
    return '1.0.0'
}

function Set-Version([string]$ver) {
    Set-Content -Path $appVersionFile -Value $ver -Encoding ASCII -NoNewline
    Add-Content -Path $appVersionFile -Value '' -Encoding ASCII
}

function Bump-Version([string]$ver) {
    $parts = $ver -split '\.'
    if ($parts.Count -lt 3) { return "$ver.1" }
    $last = [int]$parts[-1]
    $parts[-1] = [string]($last + 1)
    return ($parts -join '.')
}

$excludeNames = @(
    'launcher.log', 'first_run.done', 'gui.settings', 'work_mode.enabled',
    'xray.pid', 'xray.exe', 'Zapret.new.exe', 'test results'
)
$excludePatterns = @('*.log', '*.pid', '*.cache.txt')

$version = if ($Version) { $Version } elseif ($Bump) { Bump-Version (Get-CurrentVersion) } else { Get-CurrentVersion }
Set-Version $version

Write-Host "Version: $version" -ForegroundColor Green

$tempRoot = Join-Path $env:TEMP ("zapret-publish-" + [guid]::NewGuid().ToString())
$stageDir = Join-Path $tempRoot 'stage'
$zipPath = Join-Path $tempRoot 'Otmena-update.zip'
$configFile = Join-Path $PSScriptRoot 'update-config.json'
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($cfg.packageFile) {
            $zipPath = Join-Path $tempRoot ([string]$cfg.packageFile)
        }
    } catch {}
}
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

$includeDirs = @('app', 'bin', 'lists', 'scripts', 'telegram-vless', 'utils')
$includeFiles = @('Otmena.exe', 'README.md')

foreach ($dir in $includeDirs) {
    $src = Join-Path $rootDir $dir
    if (-not (Test-Path $src)) { continue }
    $dst = Join-Path $stageDir $dir
    Copy-Item -Path $src -Destination $dst -Recurse -Force
}

foreach ($file in $includeFiles) {
    $src = Join-Path $rootDir $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $stageDir $file) -Force
    }
}

Get-ChildItem -Path $stageDir -Recurse -Force | Where-Object {
    -not $_.PSIsContainer
} | ForEach-Object {
    $name = $_.Name
    $rel = $_.FullName.Substring($stageDir.Length)
    foreach ($ex in $excludeNames) {
        if ($name -ieq $ex) { Remove-Item -LiteralPath $_.FullName -Force; return }
    }
    foreach ($pat in $excludePatterns) {
        if ($name -like $pat) { Remove-Item -LiteralPath $_.FullName -Force; return }
    }
    if ($rel -match '\\test results\\') { Remove-Item -LiteralPath $_.FullName -Force }
}

Set-Content -Path (Join-Path $stageDir 'utils\app.version') -Value $version -Encoding ASCII
@(
    "Otmena build $version",
    ("Date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
    'Includes: MTProto LiteralPath fix, auto xray install, GitHub updates, UTF8 logs'
) | Out-File -FilePath (Join-Path $stageDir 'utils\BUILDINFO.txt') -Encoding ASCII

$skipFlag = Join-Path $stageDir 'utils\skip-xray.flag'
if (Test-Path $skipFlag) { Remove-Item $skipFlag -Force }

$xrayReadme = Join-Path $stageDir 'telegram-vless\bin\README-xray.txt'
$xrayBinDir = Split-Path $xrayReadme -Parent
if (-not (Test-Path $xrayBinDir)) { New-Item -ItemType Directory -Path $xrayBinDir -Force | Out-Null }
@(
    'xray.exe ne vkljuchen v arhiv (menshe 25 MB dlya GitHub).',
    '',
    'Pri pervom zapuske Otmena skachaet xray avtomaticheski.',
    'Istochnik 1: github.com/Qylosez/otmena-releases (fajl xray-windows-64.zip v Releases).',
    'Istochnik 2: github.com/XTLS/Xray-core/releases',
    'Esli set blokiruet - polozhi xray-windows-64.zip v etu papku i zapusti snova.'
) | Out-File -FilePath $xrayReadme -Encoding UTF8

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

$zipMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host ("Zip size: $zipMb MB") -ForegroundColor Cyan
if ($zipMb -gt 25) {
    Write-Host 'WARNING: zip bolshe 25 MB - cherez sajt GitHub mozhet ne zalitsya. Ispolzuj Releases ili gh CLI.' -ForegroundColor Yellow
}

if ($GitHubRepo) {
    $repo = $GitHubRepo.Trim()
    if ($repo -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
        $repo = $matches[1]
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw 'GitHub CLI (gh) ne ustanovlen. Skachaj s github.com/cli/cli/releases'
    }

    $tag = "v$version"
    Write-Host "GitHub release: $repo $tag" -ForegroundColor Cyan

    $null = gh release view $tag --repo $repo 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Release $tag uzhe est, obnovlyayu asset..." -ForegroundColor Yellow
        gh release upload $tag $zipPath --repo $repo --clobber
        if ($LASTEXITCODE -ne 0) { throw "gh release upload failed ($LASTEXITCODE)" }
    } else {
        gh release create $tag $zipPath --repo $repo --title "Otmena $version" --notes "Auto-update package for Otmena.exe"
        if ($LASTEXITCODE -ne 0) { throw "gh release create failed ($LASTEXITCODE)" }
    }

    Write-Host "Published: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
    Write-Host ""
    Write-Host 'Na vseh PK v utils\update-config.json:' -ForegroundColor Cyan
    Write-Host ('  "githubRepo": "' + $repo + '"') -ForegroundColor Yellow
}

if ($PublishPath) {
    if (-not (Test-Path -LiteralPath $PublishPath)) {
        New-Item -ItemType Directory -Path $PublishPath -Force | Out-Null
    }
    $zipName = Split-Path $zipPath -Leaf
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $PublishPath $zipName) -Force
    Set-Content -Path (Join-Path $PublishPath 'version.txt') -Value $version -Encoding ASCII
    Write-Host ('Published to: ' + $PublishPath) -ForegroundColor Green
    Write-Host ('  ' + $zipName) -ForegroundColor Gray
    Write-Host '  version.txt' -ForegroundColor Gray
}

Remove-Item -LiteralPath $tempRoot -Recurse -Force
