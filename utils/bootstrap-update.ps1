#Requires -Version 3.0
param(
    [switch]$Quiet,
    [switch]$FromGui,
    [string]$RootDir
)

# Standalone: works even when dropped onto Otmena 1.1.21 (old otmena-common.ps1).
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-BootLog([string]$msg) {
    Write-Output ("LOG={0}" -f $msg)
    if (-not $Quiet) { Write-Host $msg -ForegroundColor Cyan }
}

function Test-BootZip([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 200000) { return $false }
    $fs = [IO.File]::OpenRead($Path)
    try {
        return ($fs.ReadByte() -eq 0x50 -and $fs.ReadByte() -eq 0x4B -and $fs.ReadByte() -eq 0x03 -and $fs.ReadByte() -eq 0x04)
    } finally { $fs.Close() }
}

function Save-BootZip([string]$OutFile) {
    $origin = 'https://github.com/Qylosez/otmena-releases/releases/latest/download/Otmena-update.zip'
    $urls = @(
        ('https://gh-proxy.com/' + $origin),
        ('https://ghfast.top/' + $origin),
        ('https://ghproxy.net/' + $origin),
        $origin
    )
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($u in $urls) {
        try {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            if ($curl) {
                & curl.exe -fsSL --connect-timeout 12 --max-time 90 -A Otmena-Updater -o $OutFile $u 2>$null | Out-Null
            } else {
                $req = [Net.HttpWebRequest]::Create($u)
                $req.Method = 'GET'
                $req.UserAgent = 'Otmena-Updater'
                $req.Timeout = 30000
                $req.ReadWriteTimeout = 90000
                $req.AllowAutoRedirect = $true
                $req.Proxy = [Net.GlobalProxySelection]::GetEmptyWebProxy()
                $resp = $req.GetResponse()
                $in = $resp.GetResponseStream()
                $out = [IO.File]::Create($OutFile)
                try {
                    $buf = New-Object byte[] 81920
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n) }
                } finally { $out.Close(); $in.Close(); $resp.Close() }
            }
            if (Test-BootZip $OutFile) { return $true }
        } catch {}
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($extra in @(
        @('--socks5-hostname', '127.0.0.1:10808'),
        @('-x', 'http://127.0.0.1:10809')
    )) {
        if (-not $curl) { break }
        try {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            $cargs = New-Object System.Collections.Generic.List[string]
            foreach ($a in $extra) { [void]$cargs.Add($a) }
            [void]$cargs.Add('-fsSL')
            [void]$cargs.Add('--connect-timeout'); [void]$cargs.Add('12')
            [void]$cargs.Add('--max-time'); [void]$cargs.Add('90')
            [void]$cargs.Add('-A'); [void]$cargs.Add('Otmena-Updater')
            [void]$cargs.Add('-o'); [void]$cargs.Add($OutFile)
            [void]$cargs.Add($origin)
            & curl.exe @($cargs.ToArray()) 2>$null | Out-Null
            if (Test-BootZip $OutFile) { return $true }
        } catch {}
    }
    return $false
}

function Resolve-OtmenaRoot {
    if ($RootDir -and (Test-Path (Join-Path $RootDir 'Otmena.exe'))) { return (Resolve-Path $RootDir).Path }
    if ($here) {
        $fromUtils = Join-Path $here '..'
        if (Test-Path (Join-Path $fromUtils 'Otmena.exe')) { return (Resolve-Path $fromUtils).Path }
        if (Test-Path (Join-Path $here 'Otmena.exe')) { return (Resolve-Path $here).Path }
    }
    $proc = Get-Process -Name Otmena -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        $d = Split-Path $proc.Path -Parent
        if (Test-Path (Join-Path $d 'Otmena.exe')) { return $d }
    }
    foreach ($d in @(
        (Join-Path $env:USERPROFILE 'Desktop\Otmena'),
        (Join-Path $env:USERPROFILE 'Documents\Otmena'),
        'C:\Otmena',
        'D:\Otmena'
    )) {
        if (Test-Path (Join-Path $d 'Otmena.exe')) { return $d }
    }
    throw 'Ne nashla papku Otmena. Zapusti Otmena.exe i povtori.'
}

try {
    Write-BootLog '=== bootstrap update ==='
    $root = Resolve-OtmenaRoot
    Write-BootLog "Root: $root"
    $zip = Join-Path $root 'Otmena-update.zip'
    Write-BootLog 'Download zip (gh-proxy / ghfast)...'
    if (-not (Save-BootZip $zip)) {
        throw 'Ne udalos skachat zip. GitHub zablokirovan, zerkala ne otvetili. Nazhmi Zapustit vsyo i povtori.'
    }
    Write-BootLog ("Zip OK, {0} bytes" -f (Get-Item $zip).Length)

    $apply = Join-Path $root 'utils\apply-update.ps1'
    if (-not (Test-Path $apply)) { throw "Net $apply" }

    if ($FromGui) {
        Write-BootLog 'Apply from local zip...'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply -Quiet
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            Write-Output 'STATUS=scheduled'
            Write-BootLog '=== bootstrap ok ==='
            exit 0
        }
        throw "apply-update exit $code"
    }

    Get-Process -Name Otmena, Zapret -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-BootLog 'Apply in-place...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $apply -InPlace -Quiet
    if ($LASTEXITCODE -ne 0) { throw "apply-update exit $LASTEXITCODE" }
    $exe = Join-Path $root 'Otmena.exe'
    if (Test-Path $exe) { Start-Process -FilePath $exe }
    Write-Output 'STATUS=ok'
    Write-BootLog '=== bootstrap ok ==='
    exit 0
} catch {
    Write-Output ("ERROR={0}" -f $_.Exception.Message)
    Write-Output ("LOG=ERROR: {0}" -f $_.Exception.Message)
    if (-not $Quiet) { Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red }
    exit 1
}
