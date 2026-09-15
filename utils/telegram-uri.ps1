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

function Show-TelegramSocksManual {
    param([int]$Port = 10808)

    $text = @"
SOCKS5 v Telegram (vruchnuyu):

Nastrojki -> Dannye i pamjat' -> Ispol'zovanie proksi
-> Dobavit' proksi -> SOCKS5

Server: 127.0.0.1
Port: $Port
Login/parol': pusto

Vklyuchi SOCKS, esli xray podnyalsya. MTProto proxy-dag.ru ostav' kak zapasnoj.
"@
    try {
        Set-Clipboard -Value "127.0.0.1`t$Port"
    } catch {}

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            $text,
            'Telegram — SOCKS5',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        Write-Host $text -ForegroundColor Yellow
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

function Ensure-TelegramDesktopRunning {
    $running = Get-Process -Name Telegram -ErrorAction SilentlyContinue
    if ($running) { return $true }
    foreach ($p in (Get-TelegramDesktopCandidates)) {
        if (-not (Test-OtmenaPath $p)) { continue }
        try {
            Start-Process -FilePath $p | Out-Null
            Start-Sleep -Seconds 2
            return $true
        } catch {}
    }
    return $false
}

function Open-TgUriSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [switch]$Quiet,
        [string]$Kind = 'proxy'
    )

    Ensure-TelegramDesktopRunning | Out-Null

    if (-not (Test-TgUriHandler)) {
        if (-not $Quiet) {
            Write-Host 'Telegram Desktop ne privyazan k ssylkam tg://' -ForegroundColor Yellow
            Write-Host (Get-TelegramManualHint $Kind) -ForegroundColor Gray
        }
        return $false
    }

    foreach ($exe in (Get-TelegramDesktopCandidates)) {
        if (-not (Test-OtmenaPath $exe)) { continue }
        try {
            # Pass full tg:// URI via Telegram.exe -- to keep &port=... intact on Windows.
            Start-Process -FilePath $exe -ArgumentList @('--', $Uri) | Out-Null
            if (-not $Quiet) {
                Write-Host "Otkryto v Telegram: $Uri" -ForegroundColor Green
            }
            return $true
        } catch {}
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
