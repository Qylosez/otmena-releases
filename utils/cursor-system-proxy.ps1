#Requires -Version 3.0
# WinINet system proxy — Cursor/Electron on VM often ignores settings.json alone.

$ErrorActionPreference = 'SilentlyContinue'

$script:CursorRegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Update-WinInetRefresh {
    $sig = @'
[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
    try {
        $w = Add-Type -MemberDefinition $sig -Name 'WinInetOtmena' -Namespace 'Otmena' -PassThru -ErrorAction Stop
        $w::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        $w::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch {}
}

function Enable-CursorSystemProxy {
    param([int]$Port = 10809)
    Set-ItemProperty -Path $script:CursorRegPath -Name ProxyServer -Value "127.0.0.1:$Port" -Type String -Force
    Set-ItemProperty -Path $script:CursorRegPath -Name ProxyOverride -Value '<local>;localhost;127.*;10.*;172.16.*;192.168.*' -Type String -Force
    Set-ItemProperty -Path $script:CursorRegPath -Name ProxyEnable -Value 1 -Type DWord -Force
    Remove-ItemProperty -Path $script:CursorRegPath -Name AutoConfigURL -ErrorAction SilentlyContinue
    Update-WinInetRefresh
}

function Disable-CursorSystemProxy {
    Set-ItemProperty -Path $script:CursorRegPath -Name ProxyEnable -Value 0 -Type DWord -Force
    Remove-ItemProperty -Path $script:CursorRegPath -Name ProxyServer -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $script:CursorRegPath -Name ProxyOverride -ErrorAction SilentlyContinue
    Update-WinInetRefresh
}
