#Requires -Version 3.0
param(
    [ValidateSet('on', 'off', 'toggle')]
    [string]$Action = 'toggle'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'work-mode.ps1')

switch ($Action) {
    'on' {
        Enable-WorkMode
        Write-Output 'WORK=1'
        exit 0
    }
    'off' {
        Disable-WorkMode
        Write-Output 'WORK=0'
        exit 0
    }
    'toggle' {
        if (Test-WorkMode) {
            Disable-WorkMode
            Write-Output 'WORK=0'
        } else {
            Enable-WorkMode
            Write-Output 'WORK=1'
        }
        exit 0
    }
}
