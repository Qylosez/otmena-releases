#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

function Test-WorkMode {
    return Test-Path (Join-Path $PSScriptRoot 'work_mode.enabled')
}

function Enable-WorkMode {
    $flag = Join-Path $PSScriptRoot 'work_mode.enabled'
    if (-not (Test-Path $flag)) {
        Set-Content -Path $flag -Value 'enabled' -Encoding ASCII
    }
}

function Disable-WorkMode {
    $flag = Join-Path $PSScriptRoot 'work_mode.enabled'
    if (Test-Path $flag) {
        Remove-Item $flag -Force -ErrorAction SilentlyContinue
    }
}

function Test-WinwsRunning {
    return [bool](Get-Process -Name winws -ErrorAction SilentlyContinue)
}

function Test-ServiceAvailable {
    try {
        $svc = Get-Service -Name 'zapret' -ErrorAction Stop
        if ($svc.Status -eq 'Running') { return $true }
        Start-Service -Name 'zapret' -ErrorAction Stop
        Start-Sleep -Seconds 3
        return (Test-WinwsRunning)
    } catch {
        return $false
    }
}

function Start-ZapretAlt11([string]$rootDir) {
    if (Test-WinwsRunning) { return $true }
    $winws = Join-Path $rootDir 'bin\winws.exe'
    $argsFile = Join-Path $PSScriptRoot 'alt11-service-args.txt'
    if (-not (Test-Path $winws) -or -not (Test-Path $argsFile)) { return $false }
    $raw = (Get-Content -LiteralPath $argsFile -Raw -ErrorAction SilentlyContinue)
    if (-not $raw) { return $false }
    try { Unblock-File -LiteralPath $winws -ErrorAction SilentlyContinue } catch {}
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $winws
    $psi.Arguments = $raw.Trim()
    $psi.WorkingDirectory = Join-Path $rootDir 'bin'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = 'Hidden'
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    Start-Sleep -Seconds 3
    return (Test-WinwsRunning)
}

function Start-ZapretSmart([string]$rootDir) {
    $launcher = Join-Path $PSScriptRoot 'launcher.ps1'
    if (Test-Path $launcher) {
        & $launcher -Action start -Quiet
        return (Test-WinwsRunning)
    }
    if (Test-WorkMode) { return (Start-ZapretAlt11 $rootDir) }
    if (Test-ServiceAvailable) { return $true }
    Enable-WorkMode
    return (Start-ZapretAlt11 $rootDir)
}
