#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

function Test-OtmenaPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return Test-Path -Path $Path } catch { return $false }
}

function Get-TelegramDesktopCandidates {
    $list = @()
    if ($env:APPDATA) {
        $list += (Join-Path $env:APPDATA 'Telegram Desktop\Telegram.exe')
    }
    if ($env:ProgramFiles) {
        $list += (Join-Path $env:ProgramFiles 'Telegram Desktop\Telegram.exe')
    }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) {
        $list += (Join-Path $pf86 'Telegram Desktop\Telegram.exe')
    }
    return @($list | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-TgUriHandler {
    try {
        $cmd = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\tg\shell\open\command' -ErrorAction Stop).'(default)'
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
        if ($cmd -match 'WinStore|WindowsStore|LaunchUriAsync|AppInstaller') { return $false }

        if ($cmd -match '^"([^"]+)"') {
            return Test-OtmenaPath $matches[1]
        }
        $exe = ($cmd -split '\s+')[0]
        return Test-OtmenaPath $exe
    } catch {
        return $false
    }
}

function Get-TelegramManualHint([string]$kind) {
    if ($kind -eq 'socks') {
        return 'Telegram -> Nastrojki -> Proksi -> SOCKS5: 127.0.0.1 port 10808'
    }
    $cfg = Join-Path $PSScriptRoot 'telegram-mtproto.json'
    if (Test-Path $cfg) {
        try {
            $c = Get-Content $cfg -Raw | ConvertFrom-Json
            return "Telegram -> Nastrojki -> Proksi -> MTProto: $($c.server):$($c.port) secret $($c.secret)"
        } catch {}
    }
    return 'Telegram -> Nastrojki -> Proksi -> dobav MTProto vruchnuyu'
}

function Open-TgUriSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [switch]$Quiet,
        [string]$Kind = 'proxy'
    )

    if (-not (Test-TgUriHandler)) {
        if (-not $Quiet) {
            Write-Host 'Telegram Desktop ne privyazan k ssylkam tg://' -ForegroundColor Yellow
            Write-Host (Get-TelegramManualHint $Kind) -ForegroundColor Gray
        }
        return $false
    }

    try {
        Start-Process $Uri
        if (-not $Quiet) {
            Write-Host "Otkryto v Telegram: $Uri" -ForegroundColor Green
        }
        return $true
    } catch {
        if (-not $Quiet) {
            Write-Host "Ne udalos otkryt ssylku: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host (Get-TelegramManualHint $Kind) -ForegroundColor Gray
        }
        return $false
    }
}
