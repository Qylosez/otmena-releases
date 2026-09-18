#Requires -Version 3.0
param(
    [ValidateSet('start', 'stop', 'status', 'test')]
    [string]$Action = 'start',
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logFile = Join-Path $PSScriptRoot 'launcher.log'
$script:LastResults = @()

. (Join-Path $PSScriptRoot 'work-mode.ps1')
. (Join-Path $PSScriptRoot 'otmena-common.ps1')
. (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, $utf8)
    } catch {
        Add-Content -Path $logFile -Value $line -Encoding UTF8
    }
}

function Write-Info([string]$msg) {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
    Write-Log "INFO $msg"
}

function Write-Ok([string]$msg) {
    if (-not $Quiet) { Write-Host "[OK] $msg" -ForegroundColor Green }
    Write-Log "OK $msg"
}

function Write-Warn([string]$msg) {
    if (-not $Quiet) { Write-Host "[!] $msg" -ForegroundColor Yellow }
    Write-Log "WARN $msg"
}

function Write-Fail([string]$step, [string]$reason) {
    if (-not $Quiet) { Write-Host "[X] $step : $reason" -ForegroundColor Red }
    Write-Log "FAIL $step : $reason"
}

function Test-WinwsRunning {
    return [bool](Get-Process -Name winws -ErrorAction SilentlyContinue)
}

function Test-PortListen([int]$port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(1500, $false) -and $c.Connected) {
            $c.Close()
            return $true
        }
        $c.Close()
    } catch {}
    return $false
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-XrayAvailable {
    return Test-Path (Join-Path $rootDir 'telegram-vless\bin\xray.exe')
}

function Ensure-XrayInstalled {
    if (Test-XrayAvailable) { return $true }
    Write-Info 'Pervyj zapusk: ustanovka xray dlya Telegram...'
    & (Join-Path $PSScriptRoot 'ensure-xray.ps1') -Quiet | Out-Null
    if (Test-XrayAvailable) {
        Write-Ok 'xray.exe ustanovlen'
        return $true
    }
    Write-Warn 'xray ne ustanovilsya - poprobuj pozzhe ili polozhi zip v telegram-vless\bin'
    return $false
}

function Stop-Winws {
    if (-not (Test-WinwsRunning)) { return }
    taskkill /IM winws.exe /F 2>$null | Out-Null
    Start-Sleep -Seconds 1
}

function Sync-WinwsArgs {
    $sync = Join-Path $PSScriptRoot 'sync-service-args.ps1'
    if (-not (Test-Path $sync)) { return $false }
    try {
        & $sync 2>$null | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Test-CanRestartWinws {
    if (Test-IsAdmin) { return $true }
    if (Get-ScheduledTask -TaskName 'Otmena-Winws' -ErrorAction SilentlyContinue) { return $true }
    return $false
}

function Start-WinwsViaCmd {
    param([string]$RootDir)
    $bat = Join-Path $RootDir 'scripts\general (ALT11).bat'
    if (-not (Test-Path $bat)) { return $false }
    try {
        $p = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList @('/c', "`"$bat`"") `
            -WorkingDirectory $RootDir `
            -WindowStyle Hidden `
            -PassThru
        Start-Sleep -Seconds 3
        return (Test-WinwsRunning)
    } catch {
        return $false
    }
}

function Start-WinwsViaTask {
    $taskName = 'Otmena-Winws'
    if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        schtasks /Run /TN $taskName 2>$null | Out-Null
        Start-Sleep -Seconds 3
        return (Test-WinwsRunning)
    } catch {
        return $false
    }
}

function Stop-Xray {
    $pidFile = Join-Path $rootDir 'telegram-vless\xray.pid'
    if (Test-Path $pidFile) {
        $id = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($id -match '^\d+$') {
            Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    Get-Process -Name xray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    taskkill /IM xray.exe /F 2>$null | Out-Null

    $lines = netstat -ano 2>$null | Select-String 'LISTENING' | Select-String ':10808\s'
    foreach ($line in $lines) {
        if ([string]$line -match '\s(\d+)\s*$') {
            Stop-Process -Id ([int]$matches[1]) -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Seconds 1
}

function Stop-TelegramLocal {
    Stop-Xray
    . (Join-Path $PSScriptRoot 'telegram-uri.ps1')
    Open-TgUriSafe -Uri 'tg://proxy?disable=1' -Quiet -Kind 'proxy' | Out-Null
}

function Test-StartupAutostart {
    $startupDir = [Environment]::GetFolderPath('Startup')
    foreach ($name in @('Otmena.lnk', 'Zapret3.lnk', 'Zapret.lnk', 'Zapret.exe.lnk')) {
        if (Test-Path (Join-Path $startupDir $name)) { return $true }
    }
    return $false
}

function Get-ZapretStatusObject {
    $tgPort = Test-PortListen 10808
    $tgProc = [bool](Get-Process -Name xray -ErrorAction SilentlyContinue)
    $taskAuto = [bool](Get-ScheduledTask -TaskName 'Otmena-Start' -ErrorAction SilentlyContinue)
    if (-not $taskAuto) {
        $taskAuto = [bool](Get-ScheduledTask -TaskName 'Zapret-Start' -ErrorAction SilentlyContinue)
    }
    $startupAuto = Test-StartupAutostart
    $autoType = 'none'
    if ($taskAuto) { $autoType = 'task' }
    elseif ($startupAuto) { $autoType = 'startup' }
    return [PSCustomObject]@{
        ZapretRunning = Test-WinwsRunning
        TelegramRunning = ($tgPort -or $tgProc)
        WorkMode = Test-WorkMode
        IsAdmin = Test-IsAdmin
        AutostartInstalled = ($taskAuto -or $startupAuto)
        AutostartType = $autoType
    }
}

function Get-ZapretSteps {
    $steps = @()

    if (-not (Test-WorkMode)) {
        $steps += @{
            Name = 'Sluzhba Windows (zapret)'
            Group = 'Zapret'
            Try  = {
                $svc = Get-Service -Name zapret -ErrorAction SilentlyContinue
                if (-not $svc) {
                    return @{ Success = $false; Detail = 'sluzhba ne ustanovlena' }
                }
                if ($svc.Status -ne 'Running') {
                    Start-Service -Name zapret -ErrorAction Stop
                }
                Start-Sleep -Seconds 3
                if (Test-WinwsRunning) {
                    return @{ Success = $true; Detail = 'sluzhba zapushchena' }
                }
                return @{ Success = $false; Detail = 'sluzhba est, no winws ne zapustilsya' }
            }
        }
    }

    $steps += @{
        Name = 'Pryamoj zapusk winws.exe'
        Group = 'Zapret'
        Try  = {
            Sync-WinwsArgs | Out-Null
            $argsFile = Join-Path $PSScriptRoot 'alt11-service-args.txt'
            $winws = Join-Path $rootDir 'bin\winws.exe'
            if (-not (Test-Path $winws)) {
                return @{ Success = $false; Detail = 'net bin\winws.exe' }
            }
            Ensure-WlanApiDll $rootDir | Out-Null
            if (-not (Test-Path $argsFile)) {
                return @{ Success = $false; Detail = 'net argumentov zapuska' }
            }
            $raw = (Get-Content -LiteralPath $argsFile -Raw -ErrorAction SilentlyContinue)
            if (-not $raw) {
                return @{ Success = $false; Detail = 'pustye argumenty zapuska' }
            }
            $raw = $raw.Trim().Trim('"').Trim()
            if (Test-IsAdmin) {
                Start-OtmenaNativeProcess -FilePath $winws -Arguments $raw -WorkingDirectory (Join-Path $rootDir 'bin') | Out-Null
                Start-Sleep -Seconds 3
                if (Test-WinwsRunning) {
                    return @{ Success = $true; Detail = 'winws.exe napryamuyu' }
                }
            }
            if (Start-WinwsViaTask) {
                return @{ Success = $true; Detail = 'winws.exe cherez zadachu Otmena-Winws' }
            }
            if (Start-WinwsViaCmd -RootDir $rootDir) {
                return @{ Success = $true; Detail = 'winws.exe cherez ALT11.bat' }
            }
            if (-not (Test-IsAdmin)) {
                return @{ Success = $false; Detail = 'nuzhny prava admina - zapusti ZAPRET-ADMIN.bat' }
            }
            if (-not (Test-Path (Join-Path $env:WINDIR 'System32\wlanapi.dll')) -and -not (Test-Path (Join-Path $rootDir 'bin\wlanapi.dll'))) {
                return @{ Success = $false; Detail = 'net wlanapi.dll (Windows bez Wi-Fi / Server). Telegram rabotaet.' }
            }
            return @{ Success = $false; Detail = 'drajver WinDivert zablokirovan?' }
        }
    }

    return $steps
}

function Get-TelegramSteps {
    $socksPort = 10808
    $steps = @()

    if (Test-XrayAvailable) {
        $steps += @{
            Name = 'VLESS (xray, vpn.dance)'
            Group = 'Telegram'
            Try  = {
                $out = & (Join-Path $PSScriptRoot 'telegram-vless-daemon.ps1') -Quiet 2>&1 | Out-String
                $up = $false
                for ($i = 0; $i -lt 12; $i++) {
                    if (Test-PortListen $socksPort) { $up = $true; break }
                    Start-Sleep -Milliseconds 500
                }
                if ($up) {
                    & (Join-Path $PSScriptRoot 'set-telegram-socks.ps1') -Quiet 2>$null | Out-Null
                    $mode = 'SOCKS 127.0.0.1:' + $socksPort
                    if ($out -match 'XRAY_STATUS=([^\r\n]+)') { $mode += (' / ' + $matches[1]) }
                    return @{ Success = $true; Detail = $mode }
                }
                $why = 'xray ne podnyalsya'
                if ($out -match 'XRAY_STATUS=([^\r\n]+)') { $why += (' (' + $matches[1] + ')') }
                return @{ Success = $false; Detail = $why }
            }
        }
    } else {
        Write-Info 'Bez xray.exe: VLESS propuschen, ispolzuem MTProto (knopka v Otmena)'
    }

    $steps += @{
        Name = 'MTProto proxy-dag.ru'
        Group = 'Telegram'
        Try  = {
            $mtproto = Join-Path $PSScriptRoot 'set-telegram-mtproto.ps1'
            if (-not (Test-Path $mtproto)) {
                return @{ Success = $false; Detail = 'net skripta MTProto' }
            }
            try {
                & $mtproto -Quiet 2>&1 | Out-Null
            } catch {
                return @{ Success = $false; Detail = ('MTProto: ' + $_.Exception.Message) }
            }
            if ($LASTEXITCODE -eq 0) {
                return @{ Success = $true; Detail = 'proxy-dag.ru dobavlen v Telegram' }
            }
            if ($LASTEXITCODE -eq 2) {
                if (-not (Test-XrayAvailable)) {
                    return @{ Success = $true; Detail = 'skopiruj nastrojki v okne Otmena (MTProto)' }
                }
                return @{ Success = $false; Detail = 'tg:// ne otkrylsya - knopka MTProto v Otmena' }
            }
            return @{ Success = $false; Detail = 'proxy-dag.ru ne udalos dobavit' }
        }
    }

    return $steps
}

function Invoke-ZapretStep {
    param(
        [string]$Name,
        [string]$Group,
        [scriptblock]$Try,
        [switch]$RecordOnly
    )
    Write-Info "Probuyu: $Name..."
    $entry = [PSCustomObject]@{
        Group = $Group
        Name = $Name
        Success = $false
        Detail = ''
        Time = Get-Date
    }
    try {
        $result = & $Try
        if ($result.Success) {
            $entry.Success = $true
            $entry.Detail = $result.Detail
            Write-Ok "$Name - $($result.Detail)"
            $script:LastResults += $entry
            return $true
        }
        $entry.Detail = $result.Detail
        Write-Fail $Name $result.Detail
    } catch {
        $entry.Detail = $_.Exception.Message
        Write-Fail $Name $_.Exception.Message
    }
    $script:LastResults += $entry
    return $false
}

function Start-ZapretFailover {
    if (-not (Test-WlanApiPresent)) {
        Enable-WorkMode
        Write-Warn 'Windows bez Wi-Fi steka - work mode, wlanapi stub dlya winws'
    }
    Ensure-WlanApiDll $rootDir | Out-Null
    Sync-WinwsArgs | Out-Null

    $wasRunning = Test-WinwsRunning
    $canRestart = Test-CanRestartWinws

    if ($wasRunning -and -not $canRestart) {
        Write-Warn 'winws uzhe rabotaet, net prav na perezapusk - ostavlyaem kak est'
        return $true
    }

    if ($wasRunning) {
        Write-Info 'Perezapusk zapret (winws) na strategiyu 1.10.1...'
        Stop-Winws
    }

    & (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')

    foreach ($step in (Get-ZapretSteps)) {
        if (Invoke-ZapretStep -Name $step.Name -Group $step.Group -Try $step.Try) {
            return $true
        }
        if (-not (Test-WorkMode)) {
            Enable-WorkMode
            Write-Warn 'Vklyuchyon rabochij rezhim (bez sluzhby Windows)'
        }
    }

    Write-Fail 'Zapret' 'vse sposoby ne srabotali'
    if (-not (Test-IsAdmin)) {
        Write-Warn 'YouTube/Discord: zapusti ZAPRET-ADMIN.bat ot imeni administratora'
    }
    return $false
}

function Start-TelegramFailover {
    Write-Info 'Telegram: vpn.dance + SOCKS + proxy-dag.ru...'
    $out = & (Join-Path $PSScriptRoot 'apply-telegram.ps1') -Quiet 2>&1 | Out-String
    $xray = $out -match 'XRAY=1'
    $socks = $out -match 'TG_SOCKS=1'
    $mt = $out -match 'TG_MTPROTO=1'

    if ($xray -and (Test-WorkModeEnabled)) {
        . (Join-Path $PSScriptRoot 'cursor-tunnel.ps1')
        if (-not (Test-EndpointLive -Mode http -Port 10809)) {
            Write-Info 'Poisk rabochego profilya vpn.dance...'
            $probe = & (Join-Path $PSScriptRoot 'find-working-vless.ps1') -Quiet 2>&1 | Out-String
            if ($probe -match 'WORKING=1') {
                Write-Ok 'vpn.dance: najden rabochij profil'
            } else {
                Write-Warn 'vpn.dance: net rabochego profilya na etoj seti (hotspot?)'
            }
        }
    }

    if ($xray) { Write-Ok 'xray vpn.dance (SOCKS 127.0.0.1:10808)' }
    else { Write-Warn 'xray ne podnyalsya' }
    if ($mt) { Write-Ok 'proxy-dag.ru dobavlen v Telegram' }
    else { Write-Warn 'proxy-dag.ru ne otkrylsya avtomatom' }
    if ($socks) { Write-Ok 'SOCKS dobavlen v Telegram' }
    if ($xray -or $mt -or $socks) { return $true }
    Write-Warn 'Telegram: vklyuchi Desktop i nazhmi Zapustit eshchyo raz'
    return $false
}

function Test-AllMethods {
    param([switch]$LeaveBestRunning)

    $psOk = Test-PowerShellOk
    if (-not $psOk.Ok) {
        Write-Fail 'PowerShell' $psOk.Message
        return [PSCustomObject]@{ Results = @(); BestZapret = $null; BestTelegram = $null }
    }

    Ensure-XrayInstalled | Out-Null

    $script:LastResults = @()
    $wasWinws = Test-WinwsRunning
    $wasTg = Test-PortListen 10808
    $bestZapret = $null
    $bestTelegram = $null

    if (-not $LeaveBestRunning) {
        Stop-Winws
        Stop-Xray
    }

    foreach ($step in (Get-ZapretSteps)) {
        if (-not $LeaveBestRunning) { Stop-Winws }
        if (Invoke-ZapretStep -Name $step.Name -Group $step.Group -Try $step.Try) {
            if (-not $bestZapret) { $bestZapret = $step.Name }
            if (-not $LeaveBestRunning) { Stop-Winws; Start-Sleep -Seconds 1 }
        }
    }

    foreach ($step in (Get-TelegramSteps)) {
        if (-not $LeaveBestRunning) { Stop-Xray }
        if (Invoke-ZapretStep -Name $step.Name -Group $step.Group -Try $step.Try) {
            if (-not $bestTelegram) { $bestTelegram = $step.Name }
            if (-not $LeaveBestRunning) { Stop-Xray; Start-Sleep -Seconds 1 }
        }
    }

    if ($LeaveBestRunning) {
        if ($bestZapret) {
            foreach ($step in (Get-ZapretSteps)) {
                if ($step.Name -eq $bestZapret) {
                    Invoke-ZapretStep -Name $step.Name -Group $step.Group -Try $step.Try | Out-Null
                    break
                }
            }
        }
        if ($bestTelegram) {
            foreach ($step in (Get-TelegramSteps)) {
                if ($step.Name -eq $bestTelegram) {
                    Invoke-ZapretStep -Name $step.Name -Group $step.Group -Try $step.Try | Out-Null
                    break
                }
            }
        }
    } else {
        if ($wasWinws) { Start-ZapretFailover | Out-Null }
        elseif ($wasTg) { Start-TelegramFailover | Out-Null }
    }

    return [PSCustomObject]@{
        Results = $script:LastResults
        BestZapret = $bestZapret
        BestTelegram = $bestTelegram
        Status = Get-ZapretStatusObject
    }
}

function Show-Status {
    $s = Get-ZapretStatusObject
    Write-Host ''
    Write-Host '=== Status ===' -ForegroundColor White
    if ($s.ZapretRunning) {
        Write-Host '  DS/YT (zapret):  RABOTAET' -ForegroundColor Green
    } else {
        Write-Host '  DS/YT (zapret):  NE RABOTAET' -ForegroundColor Red
    }
    if ($s.TelegramRunning) {
        Write-Host '  Telegram SOCKS:  RABOTAET (127.0.0.1:10808)' -ForegroundColor Green
    } else {
        Write-Host '  Telegram SOCKS:  NE RABOTAET' -ForegroundColor Red
    }
    if ($s.WorkMode) {
        Write-Host '  Rezhim:          rabochij (bez sluzhby)' -ForegroundColor Yellow
    } else {
        Write-Host '  Rezhim:          obychnyj' -ForegroundColor Gray
    }
    if ($s.AutostartInstalled) {
        Write-Host '  Avtozapusk:      VKL' -ForegroundColor Green
    } else {
        Write-Host '  Avtozapusk:      VYKL' -ForegroundColor Gray
    }
    $ep = Get-CursorTunnelEndpoint
    $px = Test-CursorProxyEnabled
    if ($ep -and $px) {
        Write-Host ("  Cursor Europe:   RABOTAET ({0} {1})" -f $ep.Label, $ep.Port) -ForegroundColor Green
    } elseif ($ep) {
        Write-Host '  Cursor Europe:   tunnel zhiv, proksi ne zapisalsya' -ForegroundColor Yellow
    } else {
        Write-Host '  Cursor Europe:   NE RABOTAET' -ForegroundColor Red
    }
    Write-Host ''
}

function Test-SecretNet {
    try {
        $services = (sc.exe query type= service state= all 2>$null | Out-String)
        if ($services -match 'Secret|SnPolicy|SecretNet|SNPolicy') { return $true }
    } catch {}
    return $false
}

function Start-CursorEurope {
    Write-Info 'Cursor Europe: poisk zhivogo tunnel + proksi...'
    if (-not (Get-CursorTunnelEndpoint)) {
        Write-Info 'Poisk rabochego profilya vpn.dance...'
        $probe = & (Join-Path $PSScriptRoot 'find-working-vless.ps1') -Quiet 2>&1 | Out-String
        if ($probe -match 'WORKING=1') {
            Write-Ok 'vpn.dance: najden rabochij profil'
        } else {
            Write-Warn 'vpn.dance: net rabochego profilya na etoj seti'
        }
    }
    if (Enable-CursorTunnelProxy -Quiet:$Quiet) {
        return $true
    }
    Disable-CursorTunnelProxy -Quiet | Out-Null
    return $false
}

if ($MyInvocation.InvocationName -ne '.') {
switch ($Action) {
    'start' {
        if (-not $Quiet) {
            Write-Host ''
            Write-Host '=== Zapret: avto-perekljuchenie ===' -ForegroundColor White
            Write-Host ''
        }
        if (Test-SecretNet) {
            Enable-WorkMode
            Write-Warn 'Secret Net obnaruzhen - rabochij rezhim (bez sluzhby Windows)'
        }
        Ensure-XrayInstalled | Out-Null
        $deps = Ensure-OtmenaNativeDeps $rootDir
        $telegram = Start-TelegramFailover
        $zapret = Start-ZapretFailover
        $cursor = Start-CursorEurope
        if ($cursor) {
            $ep = Get-CursorTunnelEndpoint
            $url = if ($ep.Mode -eq 'socks') { "socks5://127.0.0.1:$($ep.Port)" } else { "http://127.0.0.1:$($ep.Port)" }
            Write-Ok ("Cursor Europe -> {0} ({1}). POLNOSTYU perezapusti Cursor." -f $url, $ep.Label)
        } else {
            Write-Warn 'Cursor Europe: tunnel ne otvechaet, proksi ne stavlyu (inache reconnect loop).'
        }
        if (-not $deps.WlanApi -and -not $zapret) {
            Write-Warn 'wlanapi/WinDivert: Discord/YouTube mogut ne startovat. Telegram uzhe nastroen.'
        }
        if (-not $Quiet) {
            Show-Status
        }
        if ($zapret -or $telegram -or $cursor) { exit 0 }
        exit 1
    }
    'stop' {
        Write-Info 'Ostanovka...'
        Stop-CursorWatch
        Disable-CursorTunnelProxy -Quiet:$Quiet
        Stop-Winws
        Stop-TelegramLocal
        & (Join-Path $PSScriptRoot 'disable-system-proxy.ps1')
        Write-Ok 'Ostanovleno'
        exit 0
    }
    'status' {
        Show-Status
        exit 0
    }
    'test' {
        $report = Test-AllMethods -LeaveBestRunning:(-not $Quiet)
        if (-not $Quiet) {
            Write-Host ''
            Write-Host '=== Proverka sposobov ===' -ForegroundColor White
            foreach ($r in $report.Results) {
                $mark = if ($r.Success) { '[OK]' } else { '[X]' }
                $color = if ($r.Success) { 'Green' } else { 'Red' }
                Write-Host "$mark $($r.Group) / $($r.Name): $($r.Detail)" -ForegroundColor $color
            }
            Write-Host ''
            if ($report.BestZapret) {
                Write-Host "Luchshij DS/YT: $($report.BestZapret)" -ForegroundColor Green
            } else {
                Write-Host 'Luchshij DS/YT: net rabochih' -ForegroundColor Red
            }
            if ($report.BestTelegram) {
                Write-Host "Luchshij Telegram: $($report.BestTelegram)" -ForegroundColor Green
            } else {
                Write-Host 'Luchshij Telegram: net rabochih' -ForegroundColor Red
            }
            Show-Status
        }
        if ($report.BestZapret -or $report.BestTelegram) { exit 0 }
        exit 1
    }
}
}
