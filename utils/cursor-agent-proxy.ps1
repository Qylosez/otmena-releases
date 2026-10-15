#Requires -Version 3.0
# Cursor 3.9+ ignores http.proxy unless the process itself has HTTP_PROXY
# and HTTP/2 is forced off. sqlite feature gates are best-effort.
param(
    [string]$ProxyUrl = 'http://127.0.0.1:10809',
    [switch]$Restart,
    [switch]$Clear,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$logFile = Join-Path $PSScriptRoot 'cursor-agent.log'
$backupPath = Join-Path $PSScriptRoot 'cursor-shortcuts.json'
$exePathFile = Join-Path $PSScriptRoot 'cursor.exe.path'

function Say([string]$msg) {
    if (-not $Quiet) { Write-Host $msg }
}

function Write-AgentLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch {}
    Say $msg
}

function Set-CursorChildEnv([string]$url) {
    $env:HTTP_PROXY = $url
    $env:HTTPS_PROXY = $url
    $env:ALL_PROXY = $url
    $env:http_proxy = $url
    $env:https_proxy = $url
    $env:all_proxy = $url
    $env:NO_PROXY = 'localhost,127.0.0.1,::1,.ru,.su,.xn--p1ai'
    $env:no_proxy = $env:NO_PROXY
    $env:NODE_USE_ENV_PROXY = '1'
}

function Find-CursorExe {
    $procs = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
    foreach ($proc in $procs) {
        try {
            if ($proc.Path -and (Test-Path -LiteralPath $proc.Path)) { return $proc.Path }
        } catch {}
    }
    if (Test-Path -LiteralPath $exePathFile) {
        $saved = (Get-Content -LiteralPath $exePathFile -Raw).Trim()
        if ($saved -and (Test-Path -LiteralPath $saved)) { return $saved }
    }
    foreach ($cand in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe'),
        (Join-Path $env:ProgramFiles 'Cursor\Cursor.exe')
    )) {
        if ($cand -and (Test-Path -LiteralPath $cand)) { return $cand }
    }
    return $null
}

function Get-ShortcutDirs {
    $dirs = @()
    foreach ($d in @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
    )) {
        if ($d -and (Test-Path -LiteralPath $d)) { $dirs += $d }
    }
    return $dirs
}

function Save-CursorExe([string]$exe) {
    if ($exe) {
        [IO.File]::WriteAllText($exePathFile, $exe + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false))
    }
}

function Update-CursorShortcuts([string]$exe) {
    if (-not $exe) { return 0 }
    $shell = New-Object -ComObject WScript.Shell
    $ps = (Get-Command powershell.exe).Source
    $launcher = Join-Path $PSScriptRoot 'start-cursor.ps1'
    $saved = @()
    if (Test-Path -LiteralPath $backupPath) {
        try { $saved = @((Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json)) } catch { $saved = @() }
    }
    $known = @{}
    foreach ($row in $saved) { if ($row.path) { $known[$row.path] = $true } }
    $changed = 0
    foreach ($dir in (Get-ShortcutDirs)) {
        $links = @(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue)
        foreach ($link in $links) {
            try { $sc = $shell.CreateShortcut($link.FullName) } catch { continue }
            $target = [string]$sc.TargetPath
            if ($target -notmatch '(?i)\\Cursor\.exe$') { continue }
            if (-not $known.ContainsKey($link.FullName)) {
                $saved += [PSCustomObject]@{
                    path = $link.FullName
                    target = $target
                    arguments = [string]$sc.Arguments
                    workdir = [string]$sc.WorkingDirectory
                }
                $known[$link.FullName] = $true
            }
            $sc.TargetPath = $ps
            $sc.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`""
            $sc.WorkingDirectory = Split-Path -Parent $exe
            $sc.IconLocation = "$exe,0"
            $sc.Save()
            $changed++
        }
    }
    if ($saved.Count -gt 0) {
        $saved | ConvertTo-Json -Depth 4 | Out-File -FilePath $backupPath -Encoding UTF8 -Force
    }
    return $changed
}

function Restore-CursorShortcuts {
    if (-not (Test-Path -LiteralPath $backupPath)) { return 0 }
    $rows = @()
    try { $rows = @((Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json)) } catch { return 0 }
    $shell = New-Object -ComObject WScript.Shell
    $restored = 0
    foreach ($row in $rows) {
        if (-not $row.path -or -not $row.target) { continue }
        if (-not (Test-Path -LiteralPath $row.path)) { continue }
        try {
            $sc = $shell.CreateShortcut($row.path)
            $sc.TargetPath = [string]$row.target
            $sc.Arguments = [string]$row.arguments
            $sc.WorkingDirectory = [string]$row.workdir
            $sc.IconLocation = "$($row.target),0"
            $sc.Save()
            $restored++
        } catch {}
    }
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    return $restored
}

function Restart-CursorDesktop([string]$exe, [string]$url) {
    $procs = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
    if (-not $procs) {
        Write-AgentLog 'Cursor ne zapuschen, yarlyk uzhe s proksi.'
        return $false
    }
    if (-not $exe) { $exe = Find-CursorExe }
    Set-CursorChildEnv $url
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
        Write-AgentLog 'CURSOR_RESTART=fail no-exe'
        return $false
    }
    $cursorArgs = @(
        "--proxy-server=$url",
        '--proxy-bypass-list=localhost;127.0.0.1;<local>'
    )
    Start-Process -FilePath $exe -ArgumentList $cursorArgs -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    Write-AgentLog "CURSOR_RESTART=1 exe=$exe proxy=$url"
    return $true
}

function Invoke-CursorStateSql([string]$dbPath) {
    $dll = Join-Path $PSScriptRoot 'sqlite3.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        Write-AgentLog 'sqlite3.dll missing'
        return $false
    }
    try { Unblock-File -LiteralPath $dll } catch {}
    try { Remove-Item -LiteralPath $dll -Stream Zone.Identifier -Force -ErrorAction SilentlyContinue } catch {}
    $stageDir = Join-Path $env:ProgramData 'Otmena\bin'
    $stage = Join-Path $stageDir 'sqlite3.dll'
    try {
        if (-not (Test-Path -LiteralPath $stageDir)) { New-Item -ItemType Directory -Path $stageDir -Force | Out-Null }
        Copy-Item -LiteralPath $dll -Destination $stage -Force
        Unblock-File -LiteralPath $stage -ErrorAction SilentlyContinue
    } catch {
        $stage = $dll
    }
    $cs = @'
using System;
using System.Runtime.InteropServices;
public static class OtmenaSqlite {
    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibrary(string path);
    [DllImport("sqlite3", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    public static extern int sqlite3_open16(string filename, out IntPtr db);
    [DllImport("sqlite3", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    public static extern int sqlite3_exec(IntPtr db, string sql, IntPtr cb, IntPtr arg, out IntPtr err);
    [DllImport("sqlite3", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_close(IntPtr db);
    [DllImport("sqlite3", CallingConvention = CallingConvention.Cdecl)]
    public static extern void sqlite3_free(IntPtr p);
}
'@
    if (-not ('OtmenaSqlite' -as [type])) {
        Add-Type -TypeDefinition $cs | Out-Null
    }
    $loaded = [OtmenaSqlite]::LoadLibrary($stage)
    if ($loaded -eq [IntPtr]::Zero) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-AgentLog "sqlite load failed win32=$err path=$stage"
        $loaded = [OtmenaSqlite]::LoadLibrary($dll)
        if ($loaded -eq [IntPtr]::Zero) { return $false }
    }
    $db = [IntPtr]::Zero
    $opened = [OtmenaSqlite]::sqlite3_open16($dbPath, [ref]$db)
    if ($opened -ne 0 -or $db -eq [IntPtr]::Zero) {
        Write-AgentLog "sqlite open failed code=$opened"
        return $false
    }
    $sql = @"
PRAGMA busy_timeout=4000;
INSERT OR REPLACE INTO ItemTable(key, value) VALUES ('decompose_always_local_ext_host', 'false');
INSERT OR REPLACE INTO ItemTable(key, value) VALUES ('cursor_extensions_isolation_v2', 'false');
"@
    $sqlErr = [IntPtr]::Zero
    $code = [OtmenaSqlite]::sqlite3_exec($db, $sql, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$sqlErr)
    if ($sqlErr -ne [IntPtr]::Zero) { [OtmenaSqlite]::sqlite3_free($sqlErr) }
    [OtmenaSqlite]::sqlite3_close($db) | Out-Null
    if ($code -ne 0) { Write-AgentLog "sqlite exec failed code=$code" }
    return ($code -eq 0)
}

if ($Clear) {
    $n = Restore-CursorShortcuts
    Write-AgentLog "shortcuts restored=$n"
    Write-Output 'CURSOR_AGENT=cleared'
    exit 0
}

$exe = Find-CursorExe
Save-CursorExe $exe
$links = Update-CursorShortcuts $exe
Write-AgentLog "shortcuts=$links exe=$exe"

$patched = $false
foreach ($name in @('Cursor', 'Cursor Nightly')) {
    $db = Join-Path $env:APPDATA "$name\User\globalStorage\state.vscdb"
    if (Test-Path -LiteralPath $db) {
        if (Invoke-CursorStateSql $db) { $patched = $true }
    } else {
        Write-AgentLog "no state db $db"
    }
}
Write-AgentLog ("CURSOR_AGENT=" + $(if ($patched) { 'patched' } else { 'skip' }))

if ($Restart) {
    if (Restart-CursorDesktop -exe $exe -url $ProxyUrl) {
        Write-Output 'CURSOR_RESTART=1'
    }
}
Write-Output ("CURSOR_AGENT=" + $(if ($patched) { 'patched' } else { 'skip' }))
exit 0
