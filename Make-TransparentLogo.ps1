Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$dir = $PSScriptRoot

$src  = Join-Path $dir "prism-logo.png"
$dest = Join-Path $dir "prism-logo.png"
$ico  = Join-Path $dir "prism-logo.ico"

$orig = New-Object System.Drawing.Bitmap($src)
$out  = New-Object System.Drawing.Bitmap($orig.Width, $orig.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

# Sample background from the top-left corner (well inside the dark area)
$bg  = $orig.GetPixel(8, 8)
$tol = 45   # tolerance — raise if edges look blocky, lower if logo bleeds

$rect = New-Object System.Drawing.Rectangle(0, 0, $orig.Width, $orig.Height)
$fmt  = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb

$srcData = $orig.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $fmt)
$dstData = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $fmt)

$stride = $srcData.Stride
$bytes  = $stride * $orig.Height
$srcBuf = New-Object byte[] $bytes
$dstBuf = New-Object byte[] $bytes

[System.Runtime.InteropServices.Marshal]::Copy($srcData.Scan0, $srcBuf, 0, $bytes)

for ($i = 0; $i -lt $bytes; $i += 4) {
    $b = $srcBuf[$i];   $g = $srcBuf[$i+1]; $r = $srcBuf[$i+2]; $a = $srcBuf[$i+3]
    if ([Math]::Abs($r - $bg.R) -le $tol -and
        [Math]::Abs($g - $bg.G) -le $tol -and
        [Math]::Abs($b - $bg.B) -le $tol) {
        $dstBuf[$i]   = 0; $dstBuf[$i+1] = 0; $dstBuf[$i+2] = 0; $dstBuf[$i+3] = 0
    } else {
        $dstBuf[$i]   = $b; $dstBuf[$i+1] = $g; $dstBuf[$i+2] = $r; $dstBuf[$i+3] = $a
    }
}

[System.Runtime.InteropServices.Marshal]::Copy($dstBuf, 0, $dstData.Scan0, $bytes)
$orig.UnlockBits($srcData)
$out.UnlockBits($dstData)
$orig.Dispose()

$out.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved transparent PNG: $dest" -ForegroundColor Green

# Rebuild ICO with 64, 48, 32, 16 px frames using DIB format
# (PNG-in-ICO is not supported by System.Drawing.Icon in .NET Framework / PowerShell 5.1)
$sizes = @(64, 48, 32, 16)

$dibDataList = [System.Collections.Generic.List[byte[]]]::new()
foreach ($sz in $sizes) {
    $bmp     = New-Object System.Drawing.Bitmap($out, $sz, $sz)
    $rect    = New-Object System.Drawing.Rectangle(0, 0, $sz, $sz)
    $bmpData = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $rowLen  = $sz * 4
    $srcBuf  = New-Object byte[] ($rowLen * $sz)
    [System.Runtime.InteropServices.Marshal]::Copy($bmpData.Scan0, $srcBuf, 0, $srcBuf.Length)
    $bmp.UnlockBits($bmpData)
    $bmp.Dispose()

    $andRowBytes = [int]([Math]::Ceiling($sz / 32.0)) * 4
    $andMask     = New-Object byte[] ($andRowBytes * $sz)

    $dibMs = New-Object System.IO.MemoryStream
    $dibBw = New-Object System.IO.BinaryWriter($dibMs)

    # BITMAPINFOHEADER (40 bytes)
    $dibBw.Write([uint32]40)
    $dibBw.Write([int32]$sz)
    $dibBw.Write([int32]($sz * 2))   # doubled height per ICO spec (includes AND mask)
    $dibBw.Write([uint16]1)          # biPlanes
    $dibBw.Write([uint16]32)         # biBitCount
    $dibBw.Write([uint32]0)          # biCompression BI_RGB
    $dibBw.Write([uint32]0)          # biSizeImage
    $dibBw.Write([int32]0)           # biXPelsPerMeter
    $dibBw.Write([int32]0)           # biYPelsPerMeter
    $dibBw.Write([uint32]0)          # biClrUsed
    $dibBw.Write([uint32]0)          # biClrImportant

    # Pixel data bottom-up (Format32bppArgb is BGRA in memory — matches DIB BGRA)
    for ($row = $sz - 1; $row -ge 0; $row--) {
        $dibBw.Write($srcBuf, $row * $rowLen, $rowLen)
    }

    $dibBw.Write($andMask)           # AND mask all-zero (alpha channel handles transparency)
    $dibBw.Flush()
    $dibDataList.Add($dibMs.ToArray())
    $dibBw.Dispose(); $dibMs.Dispose()
}

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

$count = $sizes.Count
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$count)

$headerSize  = 6 + 16 * $count
$imageOffset = $headerSize

for ($i = 0; $i -lt $count; $i++) {
    $bw.Write([byte]$sizes[$i])
    $bw.Write([byte]$sizes[$i])
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$dibDataList[$i].Length)
    $bw.Write([uint32]$imageOffset)
    $imageOffset += $dibDataList[$i].Length
}

for ($i = 0; $i -lt $count; $i++) {
    $bw.Write($dibDataList[$i])
}

$out.Dispose()
$bw.Flush()
[System.IO.File]::WriteAllBytes($ico, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Write-Host "Saved ICO: $ico" -ForegroundColor Green
Write-Host "Done. Run PRISM-Setup to reinstall with the new transparent icons." -ForegroundColor Cyan
