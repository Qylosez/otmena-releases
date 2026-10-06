#Requires -Version 3.0
# Tiny x64 wlanapi.dll stub for winws.exe on Windows without Wi-Fi.
$ErrorActionPreference = 'Stop'
$outFile = Join-Path $PSScriptRoot 'wlanapi.stub.dll'

function B16([uint16]$v) { [BitConverter]::GetBytes($v) }
function B32([uint32]$v) { [BitConverter]::GetBytes($v) }
function B64([uint64]$v) { [BitConverter]::GetBytes($v) }
function Add-Bytes([System.Collections.Generic.List[byte]]$dst, [byte[]]$src) {
    foreach ($b in $src) { [void]$dst.Add($b) }
}

$code = New-Object System.Collections.Generic.List[byte]
# DllMain
Add-Bytes $code ([byte[]](0x31, 0xC0, 0xB0, 0x01, 0xC3))
$fn = @{
    WlanCloseHandle    = @{ Code = [byte[]](0x31, 0xC0, 0xC3) }
    WlanEnumInterfaces = @{ Code = [byte[]](
        0x4D, 0x85, 0xC0, 0x74, 0x0A,
        0x48, 0x8D, 0x05, 0x06, 0x00, 0x00, 0x00,
        0x49, 0x89, 0x00,
        0x31, 0xC0, 0xC3,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ) }
    WlanFreeMemory     = @{ Code = [byte[]](0xC3) }
    WlanOpenHandle     = @{ Code = [byte[]](0x4D, 0x85, 0xC0, 0x74, 0x07, 0x41, 0xC7, 0x00, 0x02, 0x00, 0x00, 0x00, 0x4D, 0x85, 0xC9, 0x74, 0x07, 0x49, 0xC7, 0x01, 0x01, 0x00, 0x00, 0x00, 0x31, 0xC0, 0xC3) }
    WlanQueryInterface = @{ Code = [byte[]](0xB8, 0x90, 0x04, 0x00, 0x00, 0xC3) }
}
$order = @('WlanCloseHandle', 'WlanEnumInterfaces', 'WlanFreeMemory', 'WlanOpenHandle', 'WlanQueryInterface')
foreach ($name in $order) {
    $fn[$name].Off = $code.Count
    Add-Bytes $code $fn[$name].Code
}
while (($code.Count % 4) -ne 0) { [void]$code.Add([byte]0x90) }

$nfn = $order.Count
$edOff = $code.Count
$eatOff = $edOff + 40
$namePtrOff = $eatOff + (4 * $nfn)
$ordOff = $namePtrOff + (4 * $nfn)
$strOff = $ordOff + (2 * $nfn)

$strings = New-Object System.Collections.Generic.List[byte]
$dllNameOff = 0
Add-Bytes $strings ([Text.Encoding]::ASCII.GetBytes("wlanapi.dll"))
[void]$strings.Add(0)
$nameOffs = @{}
foreach ($name in $order) {
    $nameOffs[$name] = $strings.Count
    Add-Bytes $strings ([Text.Encoding]::ASCII.GetBytes($name))
    [void]$strings.Add(0)
}

$fileAlign = 0x200
$sectAlign = 0x1000
$headerSize = 0x400
$textRva = 0x1000
$relocRva = 0x2000
$exportSize = 40 + (4 * $nfn) + (4 * $nfn) + (2 * $nfn) + $strings.Count

Add-Bytes $code (B32 0); Add-Bytes $code (B32 0)
Add-Bytes $code (B16 0); Add-Bytes $code (B16 0)
Add-Bytes $code (B32 ($textRva + $strOff + $dllNameOff))
Add-Bytes $code (B32 1)
Add-Bytes $code (B32 $nfn)
Add-Bytes $code (B32 $nfn)
Add-Bytes $code (B32 ($textRva + $eatOff))
Add-Bytes $code (B32 ($textRva + $namePtrOff))
Add-Bytes $code (B32 ($textRva + $ordOff))
foreach ($name in $order) { Add-Bytes $code (B32 ($textRva + $fn[$name].Off)) }
foreach ($name in $order) { Add-Bytes $code (B32 ($textRva + $strOff + $nameOffs[$name])) }
for ($i = 0; $i -lt $nfn; $i++) { Add-Bytes $code (B16 $i) }
Add-Bytes $code $strings.ToArray()

$textVirtSize = $code.Count
$textRawSize = [Math]::Max($fileAlign, [int][Math]::Ceiling($textVirtSize / $fileAlign) * $fileAlign)

$reloc = New-Object System.Collections.Generic.List[byte]
Add-Bytes $reloc (B32 $textRva)
Add-Bytes $reloc (B32 12)
Add-Bytes $reloc (B16 0)
Add-Bytes $reloc (B16 0)
$relocVirtSize = $reloc.Count
$relocRawSize = $fileAlign
$sizeOfImage = $relocRva + $sectAlign
$textRawPtr = $headerSize
$relocRawPtr = $headerSize + $textRawSize

$pe = New-Object System.Collections.Generic.List[byte]
Add-Bytes $pe ([byte[]](0x4D, 0x5A))
while ($pe.Count -lt 0x3C) { [void]$pe.Add(0) }
Add-Bytes $pe (B32 0x80)
while ($pe.Count -lt 0x80) { [void]$pe.Add(0) }
Add-Bytes $pe ([byte[]](0x50, 0x45, 0x00, 0x00))
Add-Bytes $pe (B16 0x8664)
Add-Bytes $pe (B16 2)
Add-Bytes $pe (B32 0); Add-Bytes $pe (B32 0); Add-Bytes $pe (B32 0)
Add-Bytes $pe (B16 0xF0)
Add-Bytes $pe (B16 0x2022)
Add-Bytes $pe (B16 0x20B)
Add-Bytes $pe ([byte[]](14, 0))
Add-Bytes $pe (B32 $textRawSize)
Add-Bytes $pe (B32 $relocRawSize)
Add-Bytes $pe (B32 0)
Add-Bytes $pe (B32 $textRva)
Add-Bytes $pe (B32 $textRva)
Add-Bytes $pe (B64 0x180000000)
Add-Bytes $pe (B32 $sectAlign)
Add-Bytes $pe (B32 $fileAlign)
Add-Bytes $pe (B16 6); Add-Bytes $pe (B16 0)
Add-Bytes $pe (B16 0); Add-Bytes $pe (B16 0)
Add-Bytes $pe (B16 6); Add-Bytes $pe (B16 0)
Add-Bytes $pe (B32 0)
Add-Bytes $pe (B32 $sizeOfImage)
Add-Bytes $pe (B32 $headerSize)
Add-Bytes $pe (B32 0)
Add-Bytes $pe (B16 2)
Add-Bytes $pe (B16 0x160)
Add-Bytes $pe (B64 0x100000)
Add-Bytes $pe (B64 0x1000)
Add-Bytes $pe (B64 0x100000)
Add-Bytes $pe (B64 0x1000)
Add-Bytes $pe (B32 0)
Add-Bytes $pe (B32 16)
$dd = New-Object 'uint32[]' 32
$dd[0] = $textRva + $edOff
$dd[1] = $exportSize
$dd[10] = $relocRva
$dd[11] = $relocVirtSize
for ($i = 0; $i -lt 32; $i++) { Add-Bytes $pe (B32 $dd[$i]) }

function Add-Section($dst, $nm, $vsize, $vrva, $rawSize, $rawPtr, $chars) {
    $nb = [Text.Encoding]::ASCII.GetBytes($nm)
    for ($i = 0; $i -lt 8; $i++) {
        if ($i -lt $nb.Length) { [void]$dst.Add($nb[$i]) } else { [void]$dst.Add(0) }
    }
    Add-Bytes $dst (B32 $vsize)
    Add-Bytes $dst (B32 $vrva)
    Add-Bytes $dst (B32 $rawSize)
    Add-Bytes $dst (B32 $rawPtr)
    Add-Bytes $dst (B32 0); Add-Bytes $dst (B32 0)
    Add-Bytes $dst (B16 0); Add-Bytes $dst (B16 0)
    Add-Bytes $dst (B32 $chars)
}
Add-Section $pe '.text' $textVirtSize $textRva $textRawSize $textRawPtr 0x60000020
Add-Section $pe '.reloc' $relocVirtSize $relocRva $relocRawSize $relocRawPtr 0x42000040
while ($pe.Count -lt $headerSize) { [void]$pe.Add(0) }
Add-Bytes $pe $code.ToArray()
while ($pe.Count -lt ($textRawPtr + $textRawSize)) { [void]$pe.Add(0) }
Add-Bytes $pe $reloc.ToArray()
while ($pe.Count -lt ($relocRawPtr + $relocRawSize)) { [void]$pe.Add(0) }

[IO.File]::WriteAllBytes($outFile, [byte[]]$pe.ToArray())
Write-Host "Wrote $outFile ($($pe.Count) bytes) exportRva=$($textRva+$edOff) size=$exportSize"
