#Requires -Version 3.0
# DEPRECATED: use Zapret.exe in the project root instead of this script.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$utilsDir = $PSScriptRoot
$rootDir = Split-Path $utilsDir -Parent

. (Join-Path $utilsDir 'launcher.ps1')

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-StatusLabel($label, $ok, $onText, $offText) {
    if ($ok) {
        $label.Text = $onText
        $label.ForeColor = [Drawing.Color]::FromArgb(46, 160, 67)
    } else {
        $label.Text = $offText
        $label.ForeColor = [Drawing.Color]::FromArgb(220, 70, 70)
    }
}

function Append-Log($box, $text, $color) {
    if ($box.InvokeRequired) {
        [void]$box.Invoke([Action[object[]]]{
            param($args)
            Append-Log $args[0] $args[1] $args[2]
        }, @($box, $text, $color))
        return
    }
    $box.SelectionStart = $box.TextLength
    $box.SelectionLength = 0
    $box.SelectionColor = $color
    $box.AppendText("$(Get-Date -Format 'HH:mm:ss')  $text`r`n")
    $box.SelectionColor = $box.ForeColor
    $box.ScrollToCaret()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Zapret'
$form.Size = New-Object Drawing.Size(560, 660)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(24, 26, 32)
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Zapret Control'
$title.ForeColor = [Drawing.Color]::White
$title.Font = New-Object Drawing.Font('Segoe UI Semibold', 16)
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(20, 16)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Discord / YouTube + Telegram'
$subtitle.ForeColor = [Drawing.Color]::FromArgb(150, 160, 180)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object Drawing.Point(22, 48)

function New-StatusLabel($y) {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $true
    $l.Location = New-Object Drawing.Point(22, $y)
    $l.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
    return $l
}

$lblZapret = New-StatusLabel 82
$lblTg = New-StatusLabel 108
$lblMode = New-StatusLabel 134
$lblAdmin = New-StatusLabel 160
$lblAuto = New-StatusLabel 186

function New-Button($text, $x, $y, $w, $back, $fore) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object Drawing.Size($w, 42)
    $b.Location = New-Object Drawing.Point($x, $y)
    $b.FlatStyle = 'Flat'
    $b.BackColor = $back
    $b.ForeColor = $fore
    $b.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
    $b.Cursor = [Windows.Forms.Cursors]::Hand
    return $b
}

$btnStart = New-Button 'ZAPUSTIT' 20 230 160 ([Drawing.Color]::FromArgb(46, 160, 67)) ([Drawing.Color]::White)
$btnStop = New-Button 'OSTANOVIT' 190 230 160 ([Drawing.Color]::FromArgb(180, 60, 60)) ([Drawing.Color]::White)
$btnTest = New-Button 'PROVERIT VSE' 360 230 160 ([Drawing.Color]::FromArgb(55, 110, 190)) ([Drawing.Color]::White)
$btnAutoOn = New-Button 'Avtozapusk VKL' 20 285 160 ([Drawing.Color]::FromArgb(45, 50, 62)) ([Drawing.Color]::White)
$btnAutoOff = New-Button 'Avtozapusk VYKL' 190 285 160 ([Drawing.Color]::FromArgb(45, 50, 62)) ([Drawing.Color]::White)
$btnAdmin = New-Button 'Ot admina' 210 260 160 ([Drawing.Color]::FromArgb(70, 75, 90)) ([Drawing.Color]::White)
$btnClean = New-Button 'Vykl vse' 380 260 140 ([Drawing.Color]::FromArgb(120, 80, 30)) ([Drawing.Color]::White)
$btnMtproto = New-Button 'MTProto v TG' 20 310 160 ([Drawing.Color]::FromArgb(55, 110, 190)) ([Drawing.Color]::White)
$btnDelete = New-Button 'UDALIT papku' 190 310 330 ([Drawing.Color]::FromArgb(140, 40, 40)) ([Drawing.Color]::White)
$btnDelete.Height = 36

$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = New-Object Drawing.Point(20, 360)
$log.Size = New-Object Drawing.Size(500, 200)
$log.ReadOnly = $true
$log.BackColor = [Drawing.Color]::FromArgb(16, 18, 24)
$log.ForeColor = [Drawing.Color]::FromArgb(210, 215, 225)
$log.BorderStyle = 'None'
$log.Font = New-Object Drawing.Font('Consolas', 9)

$controls = @($btnStart, $btnStop, $btnTest, $btnAutoOn, $btnAutoOff, $btnAdmin, $btnClean, $btnMtproto, $btnDelete)

$refresh = {
    $s = Get-ZapretStatusObject
    Set-StatusLabel $lblZapret $s.ZapretRunning 'DS / YouTube: RABOTAET' 'DS / YouTube: VYKL'
    Set-StatusLabel $lblTg $s.TelegramRunning 'Telegram: RABOTAET (10808)' 'Telegram: VYKL'
    $lblMode.Text = if ($s.WorkMode) { 'Rezhim: rabochij (bez sluzhby)' } else { 'Rezhim: obychnyj' }
    $lblMode.ForeColor = [Drawing.Color]::FromArgb(120, 130, 150)
    Set-StatusLabel $lblAdmin $s.IsAdmin 'Prava: administrator' 'Prava: NET admina (!)'
    Set-StatusLabel $lblAuto $s.AutostartInstalled 'Avtozapusk: VKL' 'Avtozapusk: VYKL'
}
& $refresh

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ & $refresh })
$timer.Start()

function Start-UiJob {
    param(
        [scriptblock]$Work,
        [scriptblock]$Done
    )
    foreach ($c in $controls) { $c.Enabled = $false }
    $payload = @{ Work = $Work; Done = $Done }
    $bw = New-Object System.ComponentModel.BackgroundWorker
    $bw.DoWork += {
        param($sender, $e)
        $e.Result = & $e.Argument.Work
    }
    $bw.RunWorkerCompleted += {
        param($sender, $e)
        foreach ($c in $controls) { $c.Enabled = $true }
        if ($e.Error) {
            Append-Log $log "OSHIBKA: $($e.Error.Message)" ([Drawing.Color]::Red)
        } else {
            & $e.Argument.Done $e.Result
        }
        & $refresh
    }
    $bw.RunWorkerAsync($payload) | Out-Null
}

$btnStart.Add_Click({
    Append-Log $log 'Zapusk s avto-perekljucheniem...' ([Drawing.Color]::Cyan)
    Start-UiJob -Work {
        Enable-WorkMode
        $z = Start-ZapretFailover
        & (Join-Path $utilsDir 'update-cursor-exclude.ps1') 2>$null | Out-Null
        $t = Start-TelegramFailover
        @{ Zapret = $z; Telegram = $t; Log = @($script:LastResults) }
    } -Done {
        param($r)
        foreach ($entry in $r.Log) {
            $color = if ($entry.Success) { [Drawing.Color]::Green } else { [Drawing.Color]::Red }
            $mark = if ($entry.Success) { 'OK' } else { 'X' }
            Append-Log $log "[$mark] $($entry.Name): $($entry.Detail)" $color
        }
        if ($r.Zapret) { Append-Log $log 'Itog: DS/YT zapushchen' ([Drawing.Color]::Green) }
        else { Append-Log $log 'Itog: DS/YT ne zapustilsya' ([Drawing.Color]::Red) }
        if ($r.Telegram) { Append-Log $log 'Itog: Telegram zapushchen' ([Drawing.Color]::Green) }
        else { Append-Log $log 'Itog: Telegram ne zapustilsya' ([Drawing.Color]::Red) }
    }
})

$btnStop.Add_Click({
    Append-Log $log 'Ostanovka...' ([Drawing.Color]::Yellow)
    Stop-Winws
    Stop-TelegramLocal
    & (Join-Path $utilsDir 'disable-system-proxy.ps1')
    Append-Log $log 'Ostanovleno (DS/YT + Telegram SOCKS)' ([Drawing.Color]::Green)
    & $refresh
})

$btnTest.Add_Click({
    Append-Log $log 'Proverka vseh sposobov (~30 sek)...' ([Drawing.Color]::Cyan)
    Start-UiJob -Work {
        Test-AllMethods -LeaveBestRunning
    } -Done {
        param($report)
        foreach ($r in $report.Results) {
            $color = if ($r.Success) { [Drawing.Color]::Green } else { [Drawing.Color]::Red }
            $mark = if ($r.Success) { 'OK' } else { 'X' }
            Append-Log $log "[$mark] $($r.Group): $($r.Name) - $($r.Detail)" $color
        }
        if ($report.BestZapret) {
            Append-Log $log "Luchshij DS/YT: $($report.BestZapret)" ([Drawing.Color]::Green)
        } else {
            Append-Log $log 'Luchshij DS/YT: net' ([Drawing.Color]::Red)
        }
        if ($report.BestTelegram) {
            Append-Log $log "Luchshij Telegram: $($report.BestTelegram)" ([Drawing.Color]::Green)
        } else {
            Append-Log $log 'Luchshij Telegram: net' ([Drawing.Color]::Red)
        }
        Append-Log $log 'Proverka zavershena, luchshie zapushcheny' ([Drawing.Color]::Cyan)
    }
})

$btnAutoOn.Add_Click({
    if (-not (Test-IsAdmin)) {
        Append-Log $log 'Nuzhny prava administratora' ([Drawing.Color]::Red)
        return
    }
    Append-Log $log 'Ustanovka avtozapuska...' ([Drawing.Color]::Cyan)
    & (Join-Path $utilsDir 'install-autostart.ps1') | ForEach-Object { Append-Log $log $_ ([Drawing.Color]::Gray) }
    Append-Log $log 'Gotovo' ([Drawing.Color]::Green)
    & $refresh
})

$btnAutoOff.Add_Click({
    if (-not (Test-IsAdmin)) {
        Append-Log $log 'Nuzhny prava administratora' ([Drawing.Color]::Red)
        return
    }
    & (Join-Path $utilsDir 'remove-autostart.ps1') | Out-Null
    Append-Log $log 'Avtozapusk udalen' ([Drawing.Color]::Green)
    & $refresh
})

$btnAdmin.Add_Click({
    if (Test-IsAdmin) {
        Append-Log $log 'Uzhe ot administratora' ([Drawing.Color]::Green)
        return
    }
    $gui = Join-Path $utilsDir 'zapret-gui.ps1'
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$gui`"" -Verb RunAs
    $form.Close()
})

$btnClean.Add_Click({
    Append-Log $log 'Vykljuchenie vsego...' ([Drawing.Color]::Yellow)
    & (Join-Path $utilsDir 'uninstall-all.ps1')
    Append-Log $log 'Vse ostanovleno' ([Drawing.Color]::Green)
    & $refresh
})

$btnMtproto.Add_Click({
    Append-Log $log 'Dobavlyayu MTProto proxy-dag.ru v Telegram...' ([Drawing.Color]::Cyan)
    & (Join-Path $utilsDir 'set-telegram-mtproto.ps1')
    Append-Log $log 'Esli Telegram otkrylsya - najmi Enable/Vklyuchit' ([Drawing.Color]::Green)
})

$btnDelete.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show(
        'Ostanovit vse i udalit papku Zapret celykom?',
        'Udalenie',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ans -ne 'Yes') { return }
    if (-not (Test-IsAdmin)) {
        Append-Log $log 'Nuzhny prava administratora' ([Drawing.Color]::Red)
        return
    }
    & (Join-Path $utilsDir 'uninstall-all.ps1') -DeleteFolder -Quiet
    [System.Windows.Forms.MessageBox]::Show('Papka budet udalena cherez 2 sek.')
    $form.Close()
})

$form.Controls.AddRange(@(
    $title, $subtitle,
    $lblZapret, $lblTg, $lblMode, $lblAdmin, $lblAuto,
    $btnStart, $btnStop, $btnTest,
    $btnAutoOn, $btnAutoOff, $btnAdmin, $btnClean, $btnMtproto, $btnDelete,
    $log
))

Append-Log $log 'Gotov. Najmi ZAPUSTIT ili PROVERIT VSE.' ([Drawing.Color]::Gray)
if (-not (Test-IsAdmin)) {
    Append-Log $log 'VNIMANIE: net prav admina - DS/YT mozhet ne zapustitsya' ([Drawing.Color]::Orange)
}

[void]$form.ShowDialog()
