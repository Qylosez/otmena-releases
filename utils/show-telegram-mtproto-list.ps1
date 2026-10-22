#Requires -Version 3.0
$ErrorActionPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'telegram-uri.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$lines = @(Get-OtmenaMtprotoManualLines)
$body = "Если proxy-dag.ru не подключается, добавь любой другой из списка.`r`n" +
    "Telegram: Настройки -> Данные и память -> Использование прокси -> Добавить -> MTProto.`r`n" +
    "Включи один прокси. Остальные можно не включать.`r`n`r`n" +
    ($lines -join "`r`n`r`n")

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Telegram: запасные MTProto'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(640, 460)
$form.TopMost = $true
$form.MinimizeBox = $false
$form.MaximizeBox = $false

$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Font = New-Object System.Drawing.Font('Consolas', 10)
$box.Dock = 'Fill'
$box.Text = $body

$btn = New-Object System.Windows.Forms.Button
$btn.Text = 'Скопировать всё'
$btn.Dock = 'Bottom'
$btn.Height = 36
$script:MtprotoListText = $body
$btn.Add_Click({
    try { [System.Windows.Forms.Clipboard]::SetText($script:MtprotoListText) } catch {}
})

$form.Controls.Add($btn)
$form.Controls.Add($box)
[void]$form.ShowDialog()
