#Requires -Version 3.0
param(
    [string]$PngPath,
    [string]$IcoPath
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$appDir = $PSScriptRoot
if (-not $PngPath) { $PngPath = Join-Path $appDir 'otmena.png' }
if (-not $IcoPath) { $IcoPath = Join-Path $appDir 'otmena.ico' }

if (-not (Test-Path $PngPath)) {
    throw "Missing $PngPath"
}

function New-SizedBitmap([string]$path, [int]$size) {
    $src = [Drawing.Image]::FromFile($path)
    $bmp = New-Object Drawing.Bitmap $size, $size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()
    $src.Dispose()
    return $bmp
}

$sizes = @(16, 32, 48, 256)
$images = New-Object System.Collections.Generic.List[Drawing.Bitmap]
foreach ($s in $sizes) {
    [void]$images.Add((New-SizedBitmap $PngPath $s))
}

$ms = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter $ms

$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]$images.Count)

$offset = 6 + (16 * $images.Count)
$dataChunks = New-Object System.Collections.Generic.List[byte[]]

foreach ($img in $images) {
    $pngMs = New-Object IO.MemoryStream
    $img.Save($pngMs, [Drawing.Imaging.ImageFormat]::Png)
    $bytes = $pngMs.ToArray()
    $pngMs.Dispose()

    $w = [Math]::Min(255, $img.Width)
    $h = [Math]::Min(255, $img.Height)

    $writer.Write([byte]$w)
    $writer.Write([byte]$h)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$bytes.Length)
    $writer.Write([UInt32]$offset)
    $offset += $bytes.Length
    [void]$dataChunks.Add($bytes)
}

foreach ($chunk in $dataChunks) {
    $writer.Write($chunk)
}

[IO.File]::WriteAllBytes($IcoPath, $ms.ToArray())
$writer.Close()
$ms.Dispose()
foreach ($img in $images) { $img.Dispose() }

Write-Host "Created $IcoPath"
