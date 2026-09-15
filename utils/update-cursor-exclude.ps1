#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = Split-Path $PSScriptRoot -Parent
$ipsetFile = Join-Path $rootDir 'lists\ipset-exclude-user.txt'
$domainFile = Join-Path $rootDir 'lists\list-exclude-user.txt'

# Never wipe a previously working IP list if DNS is blocked this boot.
$ips = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $ipsetFile) {
    Get-Content $ipsetFile | ForEach-Object {
        if ($_ -match '^\s*(\d+\.\d+\.\d+\.\d+)(?:/\d+)?\s*$') {
            [void]$ips.Add($matches[1])
        }
    }
}

$domains = @()
if (Test-Path $domainFile) {
    $domains = Get-Content $domainFile | Where-Object {
        $_ -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*domain\.'
    } | ForEach-Object { $_.Trim().ToLower() } | Select-Object -Unique
}

$resolved = 0
foreach ($d in $domains) {
    try {
        [System.Net.Dns]::GetHostAddresses($d) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object {
            if ($ips.Add($_.IPAddressToString)) { $resolved++ }
        }
    } catch {}
}

$lines = @(
    '# Cursor/OpenAI IPs - auto-generated',
    '# Merged with previous entries so a DNS failure cannot empty this list'
)
foreach ($ip in ($ips | Sort-Object)) {
    $lines += "$ip/32"
}

$lines | Out-File -FilePath $ipsetFile -Encoding ASCII -Force
Write-Host "Updated $ipsetFile with $($ips.Count) IPv4 entries (+$resolved new)."

$svc = Get-Service -Name zapret -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host 'Restarting zapret service...'
    Restart-Service -Name zapret -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if ((Get-Service zapret).Status -eq 'Running') {
        Write-Host 'zapret restarted OK.'
    }
} else {
    Write-Host 'zapret service not running - IP exclude applies on next winws start.'
}
exit 0
