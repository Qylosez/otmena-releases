#Requires -Version 3.0
$ErrorActionPreference = 'Stop'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    try {
        & (Join-Path $PSScriptRoot 'install-autostart.ps1')
        if ($LASTEXITCODE -eq 0) {
            Write-Output 'AUTOSTART=task'
            exit 0
        }
    } catch {
        Write-Host "Task autostart failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host 'Using Startup folder (no admin task)...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'install-user-autostart.ps1')
Write-Output 'AUTOSTART=startup'
exit 0
