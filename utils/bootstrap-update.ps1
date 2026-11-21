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

function Expand-BootZip([string]$ZipPath, [string]$Dest) {
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null
    for ($i = 0; $i -lt 6; $i++) {
        try {
            $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
            break
        } catch {
            if ($i -eq 5) { throw }
            Start-Sleep -Seconds 1
        }
    }
    try {
        foreach ($entry in $archive.Entries) {
            $rel = ([string]$entry.FullName).Replace('/', '\').TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $isDir = $rel.EndsWith('\') -or [string]::IsNullOrEmpty($entry.Name)
            $target = Join-Path $Dest $rel.TrimEnd('\')
            if ($isDir) {
                if (-not (Test-Path -LiteralPath $target)) {
                    New-Item -ItemType Directory -Path $target -Force | Out-Null
                }
                continue
            }
            $parent = Split-Path -Path $target -Parent
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            $outStream = [IO.File]::Create($target)
            try {
                $inStream = $entry.Open()
                try { $inStream.CopyTo($outStream) } finally { $inStream.Dispose() }
            } finally { $outStream.Dispose() }
        }
    } finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Copy-BootTree([string]$Src, [string]$Dst) {
    Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
        $target = Join-Path $Dst $_.Name
        if ($_.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
            Copy-BootTree $_.FullName $target
        } else {
            for ($t = 0; $t -lt 8; $t++) {
                try {
                    Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop
                    break
                } catch {
                    if ($t -eq 7) { throw }
                    Start-Sleep -Milliseconds 400
                }
            }
        }
    }
}

function Install-BootPayload([string]$ZipPath, [string]$Root, [bool]$FromGui) {
    $tempRoot = Join-Path $env:TEMP ("otmena-update-" + [guid]::NewGuid().ToString())
    $extract = Join-Path $tempRoot 'extract'
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-BootLog 'Unpack zip...'
    Expand-BootZip -ZipPath $ZipPath -Dest $extract

    $payload = $extract
    $rootFiles = @(Get-ChildItem -LiteralPath $extract -File -Force -ErrorAction SilentlyContinue)
    $nested = Get-ChildItem -LiteralPath $extract -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($rootFiles.Count -eq 0 -and $nested) { $payload = $nested.FullName }

    $exeInZip = Get-ChildItem -LiteralPath $payload -Filter 'Otmena.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exeInZip) { throw 'V arhive net Otmena.exe. Zip povrezhden.' }

    if ($FromGui) {
        Write-BootLog 'Otmena otkryta — stavlyu posle zakrytiya okna...'
        $helper = Join-Path $tempRoot 'apply-helper.ps1'
        $qRoot = $Root.Replace("'", "''")
        $qPayload = $payload.Replace("'", "''")
        $qTemp = $tempRoot.Replace("'", "''")
        $qExe = (Join-Path $Root 'Otmena.exe').Replace("'", "''")
        @"
`$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds 2
Get-Process -Name Otmena,Zapret,winws -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
function Copy-Tree([string]`$src, [string]`$dst) {
    Get-ChildItem -LiteralPath `$src -Force | ForEach-Object {
        `$target = Join-Path `$dst `$_.Name
        if (`$_.PSIsContainer) {
            if (-not (Test-Path -LiteralPath `$target)) { New-Item -ItemType Directory -Path `$target -Force | Out-Null }
            Copy-Tree `$_.FullName `$target
        } else {
            for (`$t = 0; `$t -lt 8; `$t++) {
                try { Copy-Item -LiteralPath `$_.FullName -Destination `$target -Force -ErrorAction Stop; break }
                catch { Start-Sleep -Milliseconds 400 }
            }
        }
    }
}
Copy-Tree '$qPayload' '$qRoot'
`$oldExe = Join-Path '$qRoot' 'Zapret.exe'
if (Test-Path -LiteralPath `$oldExe) { Remove-Item -LiteralPath `$oldExe -Force -ErrorAction SilentlyContinue }
`$finish = Join-Path '$qRoot' 'utils\finish-update.ps1'
if (Test-Path -LiteralPath `$finish) { & `$finish }
`$sync = Join-Path '$qRoot' 'utils\sync-service-args.ps1'
if (Test-Path -LiteralPath `$sync) { try { & `$sync } catch {} }
if (Test-Path -LiteralPath '$qExe') { Start-Process -FilePath '$qExe' }
Start-Sleep -Seconds 1
Remove-Item -LiteralPath '$qTemp' -Recurse -Force -ErrorAction SilentlyContinue
"@ | Out-File -FilePath $helper -Encoding UTF8
        $argLine = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $helper + '"'
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Output 'STATUS=scheduled'
        return
    }

    Write-BootLog 'Apply in-place...'
    Get-Process -Name Otmena, Zapret, winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Copy-BootTree -Src $payload -Dst $Root
    $oldExe = Join-Path $Root 'Zapret.exe'
    if (Test-Path -LiteralPath $oldExe) { Remove-Item -LiteralPath $oldExe -Force -ErrorAction SilentlyContinue }
    $finish = Join-Path $Root 'utils\finish-update.ps1'
    if (Test-Path -LiteralPath $finish) { & $finish }
    $exe = Join-Path $Root 'Otmena.exe'
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output 'STATUS=ok'
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

    Install-BootPayload -ZipPath $zip -Root $root -FromGui:([bool]$FromGui)
    Write-BootLog '=== bootstrap ok ==='
    exit 0
} catch {
    Write-Output ("ERROR={0}" -f $_.Exception.Message)
    Write-Output ("LOG=ERROR: {0}" -f $_.Exception.Message)
    if (-not $Quiet) { Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red }
    exit 1
}
