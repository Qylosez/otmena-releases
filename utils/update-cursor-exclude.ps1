#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = Split-Path $PSScriptRoot -Parent
$ipsetFile = Join-Path $rootDir 'lists\ipset-exclude-user.txt'
$domainFile = Join-Path $rootDir 'lists\list-exclude-user.txt'

$domains = Get-Content $domainFile | Where-Object {
    $_ -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*domain\.'
} | ForEach-Object { $_.Trim().ToLower() } | Select-Object -Unique

$ips = New-Object System.Collections.Generic.HashSet[string]
foreach ($d in $domains) {
    try {
        [System.Net.Dns]::GetHostAddresses($d) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object {
            [void]$ips.Add($_.IPAddressToString)
        }
    } catch {}
}

$lines = @('# Cursor/OpenAI IPs - auto-generated', '# Re-run after zapret breaks Cursor again')
foreach ($ip in ($ips | Sort-Object)) {
    $lines += "$ip/32"
}

$lines | Out-File -FilePath $ipsetFile -Encoding ASCII -Force
Write-Host "Updated $ipsetFile with $($ips.Count) IPv4 entries."

$svc = Get-Service -Name zapret -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host 'Restarting zapret service...'
    Restart-Service -Name zapret -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if ((Get-Service zapret).Status -eq 'Running') {
        Write-Host 'zapret restarted OK.'
    }
} else {
    Write-Host 'Restart zapret manually: general (ALT11).bat or ZAPRET-ALT11-ZAPUSTIT.bat'
}
