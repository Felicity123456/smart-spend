Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
function RoundedRect($g, $brush, [single]$x, [single]$y, [single]$w, [single]$h, [single]$radius) {
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $radius * 2
    $path.AddArc($x,$y,$diameter,$diameter,180,90)
    $path.AddArc(($x+$w-$diameter),$y,$diameter,$diameter,270,90)
    $path.AddArc(($x+$w-$diameter),($y+$h-$diameter),$diameter,$diameter,0,90)
    $path.AddArc($x,($y+$h-$diameter),$diameter,$diameter,90,90)
    $path.CloseFigure(); $g.FillPath($brush,$path); $path.Dispose()
}
$bitmap = [Drawing.Bitmap]::new(1024,1024)
$g = [Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$green = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#147d64'))
$mint = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#9ce8bd'))
$white = [Drawing.Brushes]::White
$g.Clear($green.Color)
RoundedRect $g $mint 248 306 452 110 44
RoundedRect $g $white 224 360 576 394 72
RoundedRect $g $green 615 490 185 140 32
$g.FillEllipse($mint,656,542,36,36)
$pen = [Drawing.Pen]::new($green.Color,28)
$pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
$points = [Drawing.PointF[]]@([Drawing.PointF]::new(314,622),[Drawing.PointF]::new(394,542),[Drawing.PointF]::new(455,582),[Drawing.PointF]::new(548,470))
$g.DrawLines($pen,$points)
$g.DrawLines($pen,[Drawing.PointF[]]@([Drawing.PointF]::new(490,470),[Drawing.PointF]::new(548,470),[Drawing.PointF]::new(548,530)))
$bitmap.Save((Join-Path $projectRoot 'assets/branding/smartspend_logo.png'),[Drawing.Imaging.ImageFormat]::Png)
function SaveIcon([string]$path,[int]$size) {
    $image = [Drawing.Bitmap]::new($size,$size)
    $graphics = [Drawing.Graphics]::FromImage($image)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.DrawImage($bitmap,0,0,$size,$size)
    $image.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose();$image.Dispose()
}
foreach($entry in @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}.GetEnumerator()) {
    SaveIcon (Join-Path $projectRoot "android/app/src/main/res/mipmap-$($entry.Key)/ic_launcher.png") $entry.Value
    SaveIcon (Join-Path $projectRoot "android/app/src/main/res/mipmap-$($entry.Key)/ic_smartspend.png") $entry.Value
}
$catalog = Get-Content (Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
foreach($icon in $catalog.images) {
    $size = [int](([double]($icon.size.Split('x')[0])) * ([double]($icon.scale.Replace('x',''))))
    SaveIcon (Join-Path $projectRoot "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($icon.filename)") $size
}
$g.Dispose();$bitmap.Dispose();$green.Dispose();$mint.Dispose();$pen.Dispose()

