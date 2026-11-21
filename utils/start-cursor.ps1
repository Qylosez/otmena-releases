#Requires -Version 3.0
# Launch Cursor with the Otmena proxy in the process environment.
# The agent ignores settings.json unless HTTP_PROXY is set on the process itself.
$ErrorActionPreference = 'SilentlyContinue'

$utils = $PSScriptRoot
$pathFile = Join-Path $utils 'cursor.exe.path'
$exe = ''
if (Test-Path -LiteralPath $pathFile) {
    $exe = (Get-Content -LiteralPath $pathFile -Raw).Trim()
}
if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
    foreach ($cand in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe'),
        (Join-Path $env:ProgramFiles 'Cursor\Cursor.exe')
    )) {
        if ($cand -and (Test-Path -LiteralPath $cand)) { $exe = $cand; break }
    }
}
if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { exit 1 }

function Test-LocalPort([int]$port) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $wait = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        return ($wait.AsyncWaitHandle.WaitOne(400, $false) -and $client.Connected)
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch {} }
    }
}

$cursorArgs = @()
if (Test-LocalPort 10809) {
    $url = 'http://127.0.0.1:10809'
    $env:HTTP_PROXY = $url
    $env:HTTPS_PROXY = $url
    $env:ALL_PROXY = $url
    $env:http_proxy = $url
    $env:https_proxy = $url
    $env:all_proxy = $url
    $env:NO_PROXY = 'localhost,127.0.0.1,::1,.ru,.su,.xn--p1ai'
    $env:no_proxy = $env:NO_PROXY
    $env:NODE_USE_ENV_PROXY = '1'
    $cursorArgs = @(
        '--proxy-server=http://127.0.0.1:10809',
        '--proxy-bypass-list=localhost;127.0.0.1;<local>'
    )
}

Start-Process -FilePath $exe -ArgumentList $cursorArgs -WorkingDirectory (Split-Path -Parent $exe)
exit 0
