# 生成通知栏媒体按钮图标
#
# 不用矢量图:矢量图在通知 RemoteViews 里会失效(通知直接不显示)。
# 每个图标画两遍:先白色放大一版当描边,再深色正常一版当实心 ——
# 这样不管 SystemUI 给不给图标着色、通知底是浅是深,都能看清。
Add-Type -AssemblyName System.Drawing

$res = 'c:\Users\Administrator\Desktop\yin\flutter_app\android\app\src\main\res'
$densities = @{ 'mdpi' = 24; 'hdpi' = 36; 'xhdpi' = 48; 'xxhdpi' = 72; 'xxxhdpi' = 96 }

function New-Pt([int]$x, [int]$y) { New-Object System.Drawing.Point $x, $y }

function Draw-Kind($g, $brush, [string]$Kind, [int]$S) {
    function Px([double]$r) { [int][math]::Round($r * $S) }

    switch ($Kind) {
        'play' {
            $pts = [System.Drawing.Point[]]@(
                (New-Pt (Px 0.30) (Px 0.20)),
                (New-Pt (Px 0.30) (Px 0.80)),
                (New-Pt (Px 0.78) (Px 0.50)))
            $g.FillPolygon($brush, $pts)
        }
        'pause' {
            $g.FillRectangle($brush, (Px 0.30), (Px 0.20), (Px 0.14), (Px 0.60))
            $g.FillRectangle($brush, (Px 0.56), (Px 0.20), (Px 0.14), (Px 0.60))
        }
        'skip_previous' {
            $g.FillRectangle($brush, (Px 0.16), (Px 0.20), (Px 0.08), (Px 0.60))
            $pts = [System.Drawing.Point[]]@(
                (New-Pt (Px 0.28) (Px 0.50)),
                (New-Pt (Px 0.80) (Px 0.20)),
                (New-Pt (Px 0.80) (Px 0.80)))
            $g.FillPolygon($brush, $pts)
        }
        'skip_next' {
            $g.FillRectangle($brush, (Px 0.76), (Px 0.20), (Px 0.08), (Px 0.60))
            $pts = [System.Drawing.Point[]]@(
                (New-Pt (Px 0.72) (Px 0.50)),
                (New-Pt (Px 0.20) (Px 0.20)),
                (New-Pt (Px 0.20) (Px 0.80)))
            $g.FillPolygon($brush, $pts)
        }
    }
}

function New-Icon {
    param([string]$Path, [int]$S, [string]$Kind)

    $bmp = New-Object System.Drawing.Bitmap $S, $S
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
    $ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 24, 24, 24))
    $cx = [single]($S / 2); $cy = [single]($S / 2)

    # 1) 白色描边(放大版)
    $g.TranslateTransform($cx, $cy); $g.ScaleTransform([single]1.35, [single]1.35)
    $g.TranslateTransform(-$cx, -$cy)
    Draw-Kind $g $white $Kind $S
    $g.ResetTransform()

    # 2) 深色实心
    Draw-Kind $g $ink $Kind $S

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $white.Dispose(); $ink.Dispose(); $g.Dispose(); $bmp.Dispose()
}

foreach ($kind in @('play', 'pause', 'skip_previous', 'skip_next')) {
    foreach ($d in $densities.GetEnumerator()) {
        New-Icon -Path "$res\drawable-$($d.Key)\audio_service_$kind.png" -S $d.Value -Kind $kind
    }
}
Write-Host 'icons generated (outline + solid)'
