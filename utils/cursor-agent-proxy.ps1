#Requires -Version 3.0
# Cursor 3.9+ sends agent traffic over HTTP/2 directly, ignoring http.proxy.
# Force the older extension host and HTTP/1.1, then restart Cursor once so it notices.
param(
    [string]$ProxyUrl = 'http://127.0.0.1:10809',
    [switch]$Restart,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'

function Say([string]$msg) {
    if (-not $Quiet) { Write-Host $msg }
}

function Get-CursorStateDbs {
    $list = @()
    foreach ($name in @('Cursor', 'Cursor Nightly')) {
        $db = Join-Path $env:APPDATA "$name\User\globalStorage\state.vscdb"
        if (Test-Path -LiteralPath $db) { $list += $db }
    }
    return $list
}

function Invoke-CursorStateSql([string]$dbPath) {
    $dll = Join-Path $PSScriptRoot 'sqlite3.dll'
    if (-not (Test-Path -LiteralPath $dll)) { return $false }
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
    if ([OtmenaSqlite]::LoadLibrary($dll) -eq [IntPtr]::Zero) { return $false }
    $db = [IntPtr]::Zero
    $opened = [OtmenaSqlite]::sqlite3_open16($dbPath, [ref]$db)
    if ($opened -ne 0 -or $db -eq [IntPtr]::Zero) { return $false }
    $sql = @"
PRAGMA busy_timeout=4000;
INSERT OR REPLACE INTO ItemTable(key, value) VALUES ('decompose_always_local_ext_host', 'false');
INSERT OR REPLACE INTO ItemTable(key, value) VALUES ('cursor_extensions_isolation_v2', 'false');
"@
    $err = [IntPtr]::Zero
    $code = [OtmenaSqlite]::sqlite3_exec($db, $sql, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$err)
    if ($err -ne [IntPtr]::Zero) { [OtmenaSqlite]::sqlite3_free($err) }
    [OtmenaSqlite]::sqlite3_close($db) | Out-Null
    return ($code -eq 0)
}

function Restart-CursorDesktop {
    $procs = @(Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue)
    if (-not $procs) { return $false }
    $exe = $null
    foreach ($proc in $procs) {
        try {
            if ($proc.Path) { $exe = $proc.Path; break }
        } catch {}
    }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if ($exe -and (Test-Path -LiteralPath $exe)) {
        Start-Process -FilePath $exe | Out-Null
        return $true
    }
    return $false
}

$stampPath = Join-Path $PSScriptRoot 'cursor-agent.stamp'
$want = ($ProxyUrl + '|http1-agent-v1').Trim()
$prev = ''
if (Test-Path -LiteralPath $stampPath) {
    $prev = (Get-Content -LiteralPath $stampPath -Raw -ErrorAction SilentlyContinue).Trim()
}

$patched = $false
foreach ($db in (Get-CursorStateDbs)) {
    if (Invoke-CursorStateSql $db) { $patched = $true }
}

if ($patched) {
    [IO.File]::WriteAllText($stampPath, $want + [Environment]::NewLine, (New-Object Text.UTF8Encoding $false))
    Say 'Cursor agent: HTTP/1.1 proxy path restored.'
    if ($Restart -and $prev -ne $want) {
        if (Restart-CursorDesktop) {
            Say 'Cursor perezapuschen.'
            Write-Output 'CURSOR_RESTART=1'
        }
    }
    Write-Output 'CURSOR_AGENT=patched'
    exit 0
}

Write-Output 'CURSOR_AGENT=skip'
exit 0
