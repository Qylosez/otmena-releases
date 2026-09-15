#Requires -Version 3.0
# Obshie funkcii Otmena (podklyuchaj: . .\otmena-common.ps1)

# Invoke-WebRequest progress bar deadlocks when stdout is redirected (GUI).
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

function Get-GithubRepoName([string]$Repo) {
    $r = $Repo.Trim().TrimEnd('/')
    if ($r -match 'github\.com[:/](.+?)(?:\.git)?/?$') { return $matches[1] }
    return $r
}

function Get-OtmenaUpdateConfig([string]$ConfigFile) {
    if (-not (Test-OtmenaPath $ConfigFile)) { return $null }
    try { return Get-Content $ConfigFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-OtmenaWebHeaders {
    return @{
        'User-Agent' = 'Otmena-Updater'
        'Accept'     = '*/*'
    }
}

function Test-OtmenaZipFile([string]$Path, [int]$MinBytes = 50000) {
    if (-not (Test-OtmenaPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt $MinBytes) { return $false }
    $fs = [IO.File]::OpenRead($Path)
    try {
        $b0 = $fs.ReadByte(); $b1 = $fs.ReadByte(); $b2 = $fs.ReadByte(); $b3 = $fs.ReadByte()
        return ($b0 -eq 0x50 -and $b1 -eq 0x4B -and $b2 -eq 0x03 -and $b3 -eq 0x04)
    } finally { $fs.Close() }
}

function Save-OtmenaUrl([string]$Url, [string]$OutFile, [int]$TimeoutSec = 180, [int]$MinBytes = 50000) {
    $ProgressPreference = 'SilentlyContinue'
    $parent = Split-Path $OutFile -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $req = [Net.HttpWebRequest]::Create($Url)
    $req.Method = 'GET'
    $req.UserAgent = 'Otmena-Updater'
    $req.Timeout = [Math]::Max(5000, $TimeoutSec * 1000)
    $req.ReadWriteTimeout = [Math]::Max(5000, $TimeoutSec * 1000)
    $req.AllowAutoRedirect = $true
    $resp = $null
    $in = $null
    $out = $null
    try {
        $resp = $req.GetResponse()
        $in = $resp.GetResponseStream()
        $out = [IO.File]::Create($OutFile)
        $buf = New-Object byte[] 81920
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n)
        }
    } finally {
        if ($out) { $out.Close() }
        if ($in) { $in.Close() }
        if ($resp) { $resp.Close() }
    }
    if (-not (Test-OtmenaZipFile -Path $OutFile -MinBytes $MinBytes)) {
        $len = 0
        if (Test-OtmenaPath $OutFile) { $len = (Get-Item -LiteralPath $OutFile).Length }
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "skachan ne zip (size=$len). GitHub zablokirovan ili falshivyj fajl. Skachaj vruchnuyu s Releases."
    }
    return $true
}

function Get-OtmenaPackageUrl {
    param([string]$ConfigFile = (Join-Path $PSScriptRoot 'update-config.json'))

    $config = Get-OtmenaUpdateConfig $ConfigFile
    if (-not $config) { return $null }

    $packageFile = if ($config.packageFile) { [string]$config.packageFile } else { 'Otmena-update.zip' }

    if ($config.githubRepo) {
        $repo = Get-GithubRepoName ([string]$config.githubRepo)
        return "https://github.com/$repo/releases/latest/download/$packageFile"
    }

    if ($config.baseUrl) {
        $base = [string]$config.baseUrl.TrimEnd('\', '/')
        if ($base -match '^https?://') { return "$base/$packageFile" }
        return Join-Path $base $packageFile
    }
    return $null
}

function Get-OtmenaPreserveRelativePaths {
    return @(
        'utils\work_mode.enabled',
        'utils\gui.settings',
        'utils\first_run.done',
        'utils\corp_tg_hint.done',
        'utils\portable.flag',
        'utils\telegram-mtproto.json',
        'telegram-vless\subscription.json',
        'telegram-vless\subscription.cache.txt',
        'telegram-vless\bin\xray.exe',
        'telegram-vless\bin\xray-windows-64.zip',
        'telegram-vless\bin\xray-bundle.zip',
        'lists\list-general-user.txt',
        'lists\list-exclude-user.txt',
        'lists\ipset-exclude-user.txt'
    )
}

function Copy-OtmenaFile([string]$Src, [string]$Dst) {
    if (-not (Test-OtmenaPath $Src)) { return $false }
    $parent = Split-Path $Dst -Parent
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -Path $Src -Destination $Dst -Force
    return $true
}

function Test-PowerShellOk {
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        return @{ Ok = $false; Message = 'Need PowerShell 3+ (current: ' + $PSVersionTable.PSVersion + ')' }
    }
    return @{ Ok = $true; Message = $PSVersionTable.PSVersion.ToString() }
}

function Get-OtmenaAppVersion {
    $f = Join-Path $PSScriptRoot 'app.version'
    if (Test-OtmenaPath $f) {
        $v = (Get-Content $f -Raw).Trim()
        if ($v) { return $v }
    }
    return 'unknown'
}

function Unblock-OtmenaFile([string]$Path) {
    if (-not (Test-OtmenaPath $Path)) { return }
    try { Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $Path -Stream Zone.Identifier -ErrorAction SilentlyContinue } catch {}
}

function Unblock-OtmenaBinaries([string]$RootDir) {
    $paths = @(
        (Join-Path $RootDir 'Otmena.exe'),
        (Join-Path $RootDir 'bin'),
        (Join-Path $RootDir 'telegram-vless\bin')
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            Unblock-OtmenaFile $p
        } elseif (Test-Path -LiteralPath $p -PathType Container) {
            Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '\.(exe|dll|sys|bat)$' } |
                ForEach-Object { Unblock-OtmenaFile $_.FullName }
        }
    }
}

function Test-WlanApiPresent {
    $sys = Join-Path $env:WINDIR 'System32\wlanapi.dll'
    return (Test-Path -LiteralPath $sys)
}

function Start-OtmenaNativeProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [switch]$Wait,
        [int]$WaitMs = 15000
    )
    Unblock-OtmenaFile $FilePath
    if (-not $WorkingDirectory) { $WorkingDirectory = Split-Path $FilePath -Parent }
    try {
        if (-not ('OtmenaErrMode' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OtmenaErrMode {
  [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint uMode);
}
'@
        }
        # Hide abort/WER boxes like 0x40000015 (1073741845)
        [void][OtmenaErrMode]::SetErrorMode(0x0001 -bor 0x0002 -bor 0x8000)
    } catch {}
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = 'Hidden'
    $psi.ErrorDialog = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($Wait) {
        if (-not $p) { return -1 }
        if (-not $p.WaitForExit($WaitMs)) {
            try { $p.Kill() } catch {}
            return -1
        }
        return $p.ExitCode
    }
    return $p
}

function Ensure-WlanApiDll([string]$RootDir) {
    $dest = Join-Path $RootDir 'bin\wlanapi.dll'
    $sys = Join-Path $env:WINDIR 'System32\wlanapi.dll'
    $stub = Join-Path $PSScriptRoot 'wlanapi.stub.dll'
    if (Test-Path -LiteralPath $sys) {
        if (Test-Path -LiteralPath $dest) {
            try {
                if ((Get-Item -LiteralPath $dest).Length -lt 8192) {
                    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }
        return $true
    }
    if (Test-Path -LiteralPath $stub) {
        try {
            Copy-Item -LiteralPath $stub -Destination $dest -Force -ErrorAction Stop
        } catch {}
    }
    return (Test-Path -LiteralPath $dest)
}

function Ensure-OtmenaNativeDeps([string]$RootDir) {
    Unblock-OtmenaBinaries $RootDir
    $wlan = Ensure-WlanApiDll $RootDir
    return @{
        WlanApi = $wlan
        XrayUnblocked = $true
    }
}
