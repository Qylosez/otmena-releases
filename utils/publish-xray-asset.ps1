#Requires -Version 3.0
param(
    [string]$PublishPath,
    [string]$ZipName = 'xray-windows-64.zip'
)

$ErrorActionPreference = 'Stop'
if (-not $PublishPath) {
    $PublishPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'otmena-publish'
}

$outDir = $PublishPath
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$outZip = Join-Path $outDir $ZipName

if (Test-Path $outZip) {
    Write-Host "Already exists: $outZip" -ForegroundColor Green
    exit 0
}

$api = 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'
Write-Host 'Downloading latest Xray-core windows-64...' -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri $api -UseBasicParsing -TimeoutSec 30
$asset = $release.assets | Where-Object { $_.name -match 'windows-64\.zip$' } | Select-Object -First 1
if (-not $asset) { throw 'windows-64.zip not found in XTLS release' }

$tmp = Join-Path $env:TEMP ('xray-asset-' + [guid]::NewGuid().ToString() + '.zip')
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
Copy-Item -LiteralPath $tmp -Destination $outZip -Force
Remove-Item $tmp -Force

$mb = [math]::Round((Get-Item $outZip).Length / 1MB, 2)
Write-Host "Saved: $outZip ($mb MB)" -ForegroundColor Green
Write-Host ''
Write-Host 'Upload to GitHub Release (otmena-releases) as:' -ForegroundColor Cyan
Write-Host "  $ZipName" -ForegroundColor White
Write-Host 'Users will get xray on first Otmena start from this file.' -ForegroundColor Gray
