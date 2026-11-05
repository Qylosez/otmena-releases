#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'

function Test-OtmenaPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { return Test-Path -LiteralPath $Path } catch { return $false }
}

function Write-TelegramInsertLog([string]$msg) {
    $log = Join-Path $PSScriptRoot 'telegram-insert.log'
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try {
        $prev = @()
        if (Test-Path -LiteralPath $log) {
            $prev = @(Get-Content -LiteralPath $log -Tail 180 -ErrorAction SilentlyContinue)
        }
        $prev += $line
        Set-Content -LiteralPath $log -Value $prev -Encoding UTF8
    } catch {}
}

function Add-TelegramCandidate {
    param($List, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $Path = $Path.Trim().Trim('"')
    if ($Path -match '^(?i)(.*Telegram\.exe),\d+$') { $Path = $matches[1].Trim() }
    if ($Path -notmatch '(?i)Telegram\.exe$') { return }
    foreach ($e in $List) {
        if ([string]$e -ieq $Path) { return }
    }
    [void]$List.Add($Path)
}

function Get-ExeFromCommandLine([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    if ($cmd -match '(?i)"([^"]*Telegram\.exe)"') { return $matches[1] }
    if ($cmd -match '(?i)([A-Za-z]:\\[^"\r\n]*?Telegram\.exe)') { return $matches[1] }
    if ($cmd -match '(?i)(\\\\[^"\r\n]*?Telegram\.exe)') { return $matches[1] }
    return $null
}

function Get-TelegramDesktopCandidates {
    $list = New-Object System.Collections.Generic.List[string]

    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'Telegram.exe'" -ErrorAction SilentlyContinue)
        foreach ($p in $procs) {
            Add-TelegramCandidate $list ([string]$p.ExecutablePath)
        }
    } catch {}
    if ($list.Count -eq 0) {
        try {
            $procs = @(Get-WmiObject Win32_Process -Filter "Name = 'Telegram.exe'" -ErrorAction SilentlyContinue)
            foreach ($p in $procs) {
                Add-TelegramCandidate $list ([string]$p.ExecutablePath)
            }
        } catch {}
    }
    try {
        Get-Process -Name Telegram -ErrorAction SilentlyContinue | ForEach-Object {
            try { Add-TelegramCandidate $list ([string]$_.MainModule.FileName) } catch {}
        }
    } catch {}

    $regKeys = @(
        'Registry::HKEY_CURRENT_USER\Software\Classes\tg\shell\open\command',
        'Registry::HKEY_CLASSES_ROOT\tg\shell\open\command',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\tg\shell\open\command',
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\Telegram.exe',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Telegram.exe'
    )
    foreach ($k in $regKeys) {
        try {
            $item = Get-ItemProperty -LiteralPath $k -ErrorAction Stop
            Add-TelegramCandidate $list (Get-ExeFromCommandLine ([string]$item.'(default)'))
        } catch {}
    }

    $uninstallRoots = @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        try {
            Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                if ([string]$p.DisplayName -notmatch 'Telegram') { return }
                if ($p.InstallLocation) {
                    Add-TelegramCandidate $list (Join-Path ([string]$p.InstallLocation) 'Telegram.exe')
                }
                Add-TelegramCandidate $list (Get-ExeFromCommandLine ([string]$p.DisplayIcon))
            }
        } catch {}
    }

    $remembered = Join-Path $PSScriptRoot 'telegram.exe.path'
    if (Test-Path -LiteralPath $remembered) {
        $prev = Get-Content -LiteralPath $remembered -TotalCount 1 -ErrorAction SilentlyContinue
        Add-TelegramCandidate $list ([string]$prev)
    }
    if ($PSScriptRoot -match '(?i)^([A-Z]:\\Users\\[^\\]+)\\') {
        $ownerHome = $Matches[1]
        Add-TelegramCandidate $list (Join-Path $ownerHome 'AppData\Roaming\Telegram Desktop\Telegram.exe')
        Add-TelegramCandidate $list (Join-Path $ownerHome 'AppData\Local\Telegram Desktop\Telegram.exe')
    }
    if (Test-OtmenaPath 'C:\Users') {
        Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^(?i)(Public|Default|Default User|All Users)$') { return }
            Add-TelegramCandidate $list (Join-Path $_.FullName 'AppData\Roaming\Telegram Desktop\Telegram.exe')
            Add-TelegramCandidate $list (Join-Path $_.FullName 'AppData\Local\Telegram Desktop\Telegram.exe')
        }
    }

    $dirs = @()
    if ($env:APPDATA) { $dirs += (Join-Path $env:APPDATA 'Telegram Desktop') }
    if ($env:LOCALAPPDATA) { $dirs += (Join-Path $env:LOCALAPPDATA 'Telegram Desktop') }
    if ($env:ProgramFiles) { $dirs += (Join-Path $env:ProgramFiles 'Telegram Desktop') }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) { $dirs += (Join-Path $pf86 'Telegram Desktop') }
    if ($env:USERPROFILE) {
        foreach ($leaf in @('Telegram', 'Telegram Desktop')) {
            $dirs += (Join-Path $env:USERPROFILE $leaf)
            $dirs += (Join-Path (Join-Path $env:USERPROFILE 'Desktop') $leaf)
            $dirs += (Join-Path (Join-Path $env:USERPROFILE 'Downloads') $leaf)
        }
    }
    foreach ($d in $dirs) {
        Add-TelegramCandidate $list (Join-Path $d 'Telegram.exe')
    }

    foreach ($root in @(
            $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Desktop' }),
            $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'Downloads' })
        )) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-OtmenaPath $root)) { continue }
        try {
            Get-ChildItem -LiteralPath $root -Filter 'Telegram.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Select-Object -First 4 |
                ForEach-Object { Add-TelegramCandidate $list $_.FullName }
        } catch {}
    }

    $lnkRoots = @()
    if ($env:APPDATA) { $lnkRoots += (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') }
    if ($env:ProgramData) { $lnkRoots += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') }
    if ($env:USERPROFILE) { $lnkRoots += (Join-Path $env:USERPROFILE 'Desktop') }
    $sh = $null
    try { $sh = New-Object -ComObject WScript.Shell } catch {}
    if ($sh) {
        foreach ($root in $lnkRoots) {
            if (-not (Test-OtmenaPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -Filter '*elegram*.lnk' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 12 |
                ForEach-Object {
                    try {
                        $sc = $sh.CreateShortcut($_.FullName)
                        Add-TelegramCandidate $list ([string]$sc.TargetPath)
                    } catch {}
                }
        }
    }

    $existing = @()
    foreach ($p in $list) {
        if (Test-OtmenaPath $p) { $existing += $p }
    }
    $desktop = @($existing | Where-Object { $_ -notmatch '\\WindowsApps\\' })
    $store = @($existing | Where-Object { $_ -match '\\WindowsApps\\' })
    $pick = @($desktop + $store)
    if ($pick.Count -gt 0) {
        try {
            Set-Content -LiteralPath (Join-Path $PSScriptRoot 'telegram.exe.path') -Value $pick[0] -Encoding ASCII
        } catch {}
    }
    return $pick
}

function Test-TgUriHandler {
    try {
        $cmd = (Get-ItemProperty 'Registry::HKEY_CLASSES_ROOT\tg\shell\open\command' -ErrorAction Stop).'(default)'
        if ([string]::IsNullOrWhiteSpace($cmd)) { return $false }
        if ($cmd -match 'WinStore|WindowsStore|LaunchUriAsync|AppInstaller|WindowsApps') { return $false }
        $exe = Get-ExeFromCommandLine $cmd
        if ($exe) { return Test-OtmenaPath $exe }
        return $false
    } catch {
        return $false
    }
}

function Get-TelegramArguments([string]$Uri) {
    if ([string]::IsNullOrWhiteSpace($Uri)) { return '' }
    $safe = $Uri -replace '"', ''
    return '-- "' + $safe + '"'
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
    if (Test-Path -LiteralPath $cfg) {
        try {
            $c = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json
            return "Telegram -> Nastrojki -> Proksi -> MTProto: $($c.server):$($c.port) secret $($c.secret)"
        } catch {}
    }
    return 'Telegram -> Nastrojki -> Proksi -> dobav MTProto vruchnuyu'
}

function Test-TelegramProcessRunning {
    return [bool](Get-Process -Name Telegram -ErrorAction SilentlyContinue)
}

function Start-TelegramWithUri {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string]$Uri
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = Get-TelegramArguments $Uri
    $psi.UseShellExecute = $true
    $psi.WorkingDirectory = Split-Path -Parent $Exe
    [void][System.Diagnostics.Process]::Start($psi)
}

function Open-TgUriSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [switch]$Quiet,
        [string]$Kind = 'proxy'
    )

    $exes = @(Get-TelegramDesktopCandidates)
    if ($exes.Count -eq 0) {
        Write-TelegramInsertLog ("no Telegram.exe for {0}; tg-handler={1}" -f $Kind, [int](Test-TgUriHandler))
        if (-not $Quiet) {
            Write-Host 'Telegram Desktop ne najden. Versiya iz Microsoft Store ne prinimaet klyuch.' -ForegroundColor Yellow
            Write-Host (Get-TelegramManualHint $Kind) -ForegroundColor Gray
        }
        return $false
    }

    $wasRunning = Test-TelegramProcessRunning
    foreach ($exe in $exes) {
        try {
            Start-TelegramWithUri -Exe $exe -Uri $Uri
            if (-not $wasRunning) {
                $deadline = (Get-Date).AddSeconds(8)
                while ((Get-Date) -lt $deadline) {
                    if (Test-TelegramProcessRunning) { break }
                    Start-Sleep -Milliseconds 300
                }
                Start-Sleep -Milliseconds 1500
            } else {
                Start-Sleep -Milliseconds 1200
            }
            Write-TelegramInsertLog ("opened {0} via {1} args={2}" -f $Kind, $exe, (Get-TelegramArguments $Uri))
            if (-not $Quiet) {
                Write-Host "Otkryto v Telegram: $Uri" -ForegroundColor Green
            }
            return $true
        } catch {
            Write-TelegramInsertLog ("fail {0} {1} {2}" -f $Kind, $exe, $_.Exception.Message)
        }
    }

    if (-not $Quiet) {
        Write-Host 'Ne udalos peredat ssylku v Telegram.exe' -ForegroundColor Red
        Write-Host (Get-TelegramManualHint $Kind) -ForegroundColor Gray
    }
    return $false
}

function Get-OtmenaMtprotoList {
    # PowerShell 5.1 collapses a JSON array into one value and prints
    # System.Object[] instead of the server. Read each object as text.
    $path = Join-Path $PSScriptRoot 'telegram-mtproto-list.json'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $text = ''
    try { $text = [System.IO.File]::ReadAllText($path) } catch { return }
    $rx = [regex]'\{[^{}]*\}'
    foreach ($m in $rx.Matches($text)) {
        $block = [string]$m.Value
        if ($block -notmatch '"server"\s*:\s*"([^"]+)"') { continue }
        $server = [string]$Matches[1]
        $port = 443
        if ($block -match '"port"\s*:\s*(\d+)') { $port = [int]$Matches[1] }
        if ($block -notmatch '"secret"\s*:\s*"([^"]+)"') { continue }
        $secret = [string]$Matches[1]
        if (-not $server -or -not $secret) { continue }
        Write-Output ([PSCustomObject]@{ server = $server; port = $port; secret = $secret })
    }
}

function Get-OtmenaMtprotoManualLines {
    $lines = New-Object System.Collections.Generic.List[string]
    $n = 1
    foreach ($p in (Get-OtmenaMtprotoList)) {
        $server = [string]$p.server
        $secret = [string]$p.secret
        if (-not $server -or -not $secret) { continue }
        if ($server -eq 'System.Object[]' -or $secret -eq 'System.Object[]') { continue }
        $port = 443
        if ($p.port) { $port = [int]$p.port }
        [void]$lines.Add(('{0}) {1}:{2} secret {3}' -f $n, $server, $port, $secret))
        $n++
    }
    foreach ($line in $lines) { Write-Output $line }
}

function Show-OtmenaMtprotoList {
    $shower = Join-Path $PSScriptRoot 'show-telegram-mtproto-list.ps1'
    if (-not (Test-Path -LiteralPath $shower)) { return }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $shower + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        [void][System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-TelegramInsertLog ("mtproto list window: {0}" -f $_.Exception.Message)
    }
}
