#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Test-SecretNet {
    foreach ($name in @('SnPolicy', 'SecretNet', 'SNSession', 'snbs', 'SecretNetStudio', 'SNService')) {
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($svc) { return $true }
        } catch {}
    }
    try {
        $out = (sc.exe query SnPolicy 2>&1 | Out-String)
        if ($out -match 'SERVICE_NAME') { return $true }
    } catch {}
    return $false
}

function Test-StartupShortcut {
    $startupDir = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
        if (Test-Path (Join-Path $startupDir $name)) { return $true }
    }
    return $false
}

$workFlag = Join-Path $PSScriptRoot 'work_mode.enabled'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$p = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output ("SECRETNET={0}" -f [int](Test-SecretNet))
Write-Output ("WORK={0}" -f [int](Test-Path $workFlag))
Write-Output ("ADMIN={0}" -f [int]$isAdmin)
Write-Output ("XRAY={0}" -f [int](Test-Path (Join-Path $rootDir 'telegram-vless\bin\xray.exe')))
Write-Output ("PORTABLE={0}" -f [int](Test-Path (Join-Path $PSScriptRoot 'portable.flag')))
