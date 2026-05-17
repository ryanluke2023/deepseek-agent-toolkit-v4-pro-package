#requires -Version 5.1
<#
Universal Icon Toolkit GUI - Fixed
用途：
1. 选择 PNG/JPG 图片
2. 自动生成 Windows .ico 多尺寸图标
3. 自动复制图标到项目目录
4. 自动修补 ps2exe 打包脚本，加入 -iconFile
5. 自动修补 Inno Setup .iss，加入 SetupIconFile 和 [Files] 图标项
6. 生成 ICON-README.md

启动：
powershell -ExecutionPolicy Bypass -File .\universal-icon-toolkit-gui-fixed.ps1
#>

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$Script:OutputDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Universal-Icon-Toolkit-Output"
New-Item -ItemType Directory -Force -Path $Script:OutputDir | Out-Null
$Script:LogPath = Join-Path $Script:OutputDir ("icon-toolkit-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

function Add-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","OK","WARN","FAIL","STEP")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message

    if ($Script:LogBox) {
        $Script:LogBox.AppendText($line + [Environment]::NewLine)
        $Script:LogBox.SelectionStart = $Script:LogBox.Text.Length
        $Script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8
}

function Show-Info {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "Universal Icon Toolkit", "OK", "Information") | Out-Null
}

function Show-Warn {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "提示", "OK", "Warning") | Out-Null
}

function Show-Err {
    param([string]$Text)
    [System.Windows.Forms.MessageBox]::Show($Text, "错误", "OK", "Error") | Out-Null
}

function Select-ImageFile {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "选择图标源图片"
    $dlg.Filter = "Image Files|*.png;*.jpg;*.jpeg;*.bmp|All Files|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Script:InputImageText.Text = $dlg.FileName
        Add-Log "已选择图片：$($dlg.FileName)" "OK"
    }
}

function Select-ProjectDir {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "选择项目目录"
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Script:ProjectDirText.Text = $dlg.SelectedPath
        Add-Log "已选择项目目录：$($dlg.SelectedPath)" "OK"
    }
}

function Convert-ImageToIcon {
    param(
        [string]$InputImage,
        [string]$OutputIcon
    )

    Add-Log "开始生成 ICO 图标..." "STEP"

    if (-not (Test-Path $InputImage)) {
        throw "图片不存在：$InputImage"
    }

    $source = [System.Drawing.Image]::FromFile($InputImage)

    try {
        $sizes = @(16, 24, 32, 48, 64, 128, 256)
        $bitmaps = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]

        foreach ($s in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap $s, $s
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)

                $ratio = [Math]::Min($s / $source.Width, $s / $source.Height)
                $w = [int]($source.Width * $ratio)
                $h = [int]($source.Height * $ratio)
                $x = [int](($s - $w) / 2)
                $y = [int](($s - $h) / 2)

                $graphics.DrawImage($source, $x, $y, $w, $h)
            } finally {
                $graphics.Dispose()
            }
            $bitmaps.Add($bmp)
        }

        # 写入 ICO 文件
        $fs = [System.IO.File]::Create($OutputIcon)
        try {
            $bw = New-Object System.IO.BinaryWriter($fs)

            # ICO header
            $bw.Write([UInt16]0)              # reserved
            $bw.Write([UInt16]1)              # icon type
            $bw.Write([UInt16]$bitmaps.Count) # image count

            $pngBytesList = New-Object System.Collections.Generic.List[byte[]]

            foreach ($bmp in $bitmaps) {
                $ms = New-Object System.IO.MemoryStream
                $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                $pngBytes = $ms.ToArray()
                $pngBytesList.Add($pngBytes)
                $ms.Dispose()
            }

            $offset = 6 + (16 * $bitmaps.Count)

            for ($i = 0; $i -lt $bitmaps.Count; $i++) {
                $bmp = $bitmaps[$i]
                $pngBytes = $pngBytesList[$i]
                $widthByte = if ($bmp.Width -eq 256) { 0 } else { [byte]$bmp.Width }
                $heightByte = if ($bmp.Height -eq 256) { 0 } else { [byte]$bmp.Height }

                $bw.Write([byte]$widthByte)
                $bw.Write([byte]$heightByte)
                $bw.Write([byte]0) # color count
                $bw.Write([byte]0) # reserved
                $bw.Write([UInt16]1) # planes
                $bw.Write([UInt16]32) # bit count
                $bw.Write([UInt32]$pngBytes.Length)
                $bw.Write([UInt32]$offset)

                $offset += $pngBytes.Length
            }

            foreach ($pngBytes in $pngBytesList) {
                $bw.Write($pngBytes)
            }

            $bw.Flush()
        } finally {
            $fs.Dispose()
            foreach ($bmp in $bitmaps) {
                $bmp.Dispose()
            }
        }
    } finally {
        $source.Dispose()
    }

    Add-Log "ICO 图标生成完成：$OutputIcon" "OK"
}

function Copy-IconToProject {
    param(
        [string]$IconPath,
        [string]$ProjectDir,
        [string]$IconName
    )

    if (-not (Test-Path $ProjectDir)) {
        throw "项目目录不存在：$ProjectDir"
    }

    $dest = Join-Path $ProjectDir $IconName
    Copy-Item $IconPath $dest -Force
    Add-Log "图标已复制到项目目录：$dest" "OK"
    return $dest
}

function Update-Ps2ExeBuildScript {
    param(
        [string]$ProjectDir,
        [string]$IconName
    )

    $candidates = @(
        "build-v4-pro-installer.ps1",
        "build-v4-exe.ps1",
        "build-installer.ps1"
    )

    $buildScriptPath = $null

    foreach ($name in $candidates) {
        $p = Join-Path $ProjectDir $name
        if (Test-Path $p) {
            $buildScriptPath = $p
            break
        }
    }

    if (-not $buildScriptPath) {
        Add-Log "未找到 build 脚本，跳过 ps2exe 自动修补。" "WARN"
        return
    }

    $text = Get-Content -Raw -LiteralPath $buildScriptPath -Encoding UTF8

    if ($text -notmatch '\$IconPath\s*=') {
        $insert = "`r`n`$IconPath = Join-Path `$Root `"$IconName`"`r`n"
        $text = $text -replace '(\$ExePath\s*=.*?(\r?\n))', "`$1$insert"
    }

    if ($text -notmatch '-iconFile\s+\$IconPath') {
        $text = $text -replace '(-version\s+"[^"]+"\s*`?\r?\n)', "`$1    -iconFile `$IconPath ``r`n"
    }

    [System.IO.File]::WriteAllText($buildScriptPath, $text, $Script:Utf8Bom)
    Add-Log "已更新 ps2exe 打包脚本：$buildScriptPath" "OK"
}

function Update-InnoSetupFile {
    param(
        [string]$ProjectDir,
        [string]$IconName
    )

    $issFiles = Get-ChildItem -Path $ProjectDir -Filter "*.iss" -File -ErrorAction SilentlyContinue

    if (-not $issFiles -or $issFiles.Count -eq 0) {
        Add-Log "未找到 .iss 文件，跳过 Inno Setup 自动修补。" "WARN"
        return
    }

    $issPath = $issFiles[0].FullName
    $text = Get-Content -Raw -LiteralPath $issPath -Encoding UTF8

    if ($text -notmatch 'SetupIconFile\s*=') {
        $text = $text -replace '(\[Setup\]\s*)', "`$1`r`nSetupIconFile=$IconName`r`n"
    } else {
        $text = $text -replace 'SetupIconFile\s*=.*', "SetupIconFile=$IconName"
    }

    $fileLine = 'Source: "' + $IconName + '"; DestDir: "{app}"; Flags: ignoreversion'

    if ($text -notmatch [regex]::Escape($fileLine)) {
        if ($text -match '\[Files\]') {
            $text = $text -replace '(\[Files\]\s*)', "`$1`r`n$fileLine`r`n"
        } else {
            $text += "`r`n[Files]`r`n$fileLine`r`n"
        }
    }

    [System.IO.File]::WriteAllText($issPath, $text, $Script:Utf8Bom)
    Add-Log "已更新 Inno Setup 配置：$issPath" "OK"
}

function Write-IconReadme {
    param(
        [string]$ProjectDir,
        [string]$IconName
    )

    $readme = @"
# 图标接入说明

## 已生成图标

文件名：

```text
$IconName
```

## 主程序 EXE 图标

ps2exe 打包脚本应包含：

```powershell
`$IconPath = Join-Path `$Root "$IconName"

Invoke-ps2exe `
    -inputFile `$SourcePs1 `
    -outputFile `$ExePath `
    -iconFile `$IconPath `
    -noConsole `
    -STA
```

## 安装包图标

Inno Setup `.iss` 文件应包含：

```ini
[Setup]
SetupIconFile=$IconName

[Files]
Source: "$IconName"; DestDir: "{app}"; Flags: ignoreversion
```

## 如果图标没有马上显示

可以尝试：

1. 刷新文件夹
2. 改 EXE 文件名重新生成
3. 重启资源管理器
4. 重启电脑

"@

    $path = Join-Path $ProjectDir "ICON-README.md"
    [System.IO.File]::WriteAllText($path, $readme, $Script:Utf8Bom)
    Add-Log "已生成说明文件：$path" "OK"
}

function Run-All {
    try {
        $input = $Script:InputImageText.Text.Trim()
        $project = $Script:ProjectDirText.Text.Trim()
        $iconName = $Script:IconNameText.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($input) -or -not (Test-Path $input)) {
            Show-Warn "请先选择有效的图片文件。"
            return
        }

        if ([string]::IsNullOrWhiteSpace($project) -or -not (Test-Path $project)) {
            Show-Warn "请先选择有效的项目目录。"
            return
        }

        if ([string]::IsNullOrWhiteSpace($iconName)) {
            $iconName = "app.ico"
        }

        if (-not $iconName.ToLower().EndsWith(".ico")) {
            $iconName = $iconName + ".ico"
        }

        Add-Log "========== 开始一键生成并接入图标 ==========" "STEP"

        $outputIcon = Join-Path $Script:OutputDir $iconName
        Convert-ImageToIcon -InputImage $input -OutputIcon $outputIcon

        $projectIcon = Copy-IconToProject -IconPath $outputIcon -ProjectDir $project -IconName $iconName

        Update-Ps2ExeBuildScript -ProjectDir $project -IconName $iconName
        Update-InnoSetupFile -ProjectDir $project -IconName $iconName
        Write-IconReadme -ProjectDir $project -IconName $iconName

        Add-Log "========== 完成 ==========" "OK"

        Show-Info "图标已生成并接入项目。`n`n项目图标：$projectIcon"
        Start-Process explorer.exe $project
    } catch {
        Add-Log "执行失败：$($_.Exception.Message)" "FAIL"
        Show-Err "执行失败：$($_.Exception.Message)"
    }
}

# =========================
# GUI
# =========================

[System.Windows.Forms.Application]::EnableVisualStyles()

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Universal Icon Toolkit GUI - Fixed"
$Form.Size = New-Object System.Drawing.Size(820, 560)
$Form.StartPosition = "CenterScreen"
$Form.BackColor = [System.Drawing.Color]::FromArgb(248,250,252)
$Form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

$Title = New-Object System.Windows.Forms.Label
$Title.Text = "Universal Icon Toolkit GUI 修复版"
$Title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 16, [System.Drawing.FontStyle]::Bold)
$Title.Location = New-Object System.Drawing.Point(20, 18)
$Title.Size = New-Object System.Drawing.Size(760, 34)
$Form.Controls.Add($Title)

$Sub = New-Object System.Windows.Forms.Label
$Sub.Text = "PNG/JPG → ICO，多尺寸图标生成，并自动接入 ps2exe 与 Inno Setup"
$Sub.Location = New-Object System.Drawing.Point(22, 58)
$Sub.Size = New-Object System.Drawing.Size(760, 24)
$Form.Controls.Add($Sub)

$Group = New-Object System.Windows.Forms.GroupBox
$Group.Text = "配置"
$Group.Location = New-Object System.Drawing.Point(20, 95)
$Group.Size = New-Object System.Drawing.Size(760, 210)
$Group.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($Group)

$ImgLabel = New-Object System.Windows.Forms.Label
$ImgLabel.Text = "源图片"
$ImgLabel.Location = New-Object System.Drawing.Point(20, 35)
$ImgLabel.Size = New-Object System.Drawing.Size(80, 24)
$Group.Controls.Add($ImgLabel)

$Script:InputImageText = New-Object System.Windows.Forms.TextBox
$Script:InputImageText.Location = New-Object System.Drawing.Point(100, 32)
$Script:InputImageText.Size = New-Object System.Drawing.Size(520, 26)
$Group.Controls.Add($Script:InputImageText)

$BtnImg = New-Object System.Windows.Forms.Button
$BtnImg.Text = "选择图片"
$BtnImg.Location = New-Object System.Drawing.Point(635, 30)
$BtnImg.Size = New-Object System.Drawing.Size(100, 30)
$BtnImg.Add_Click({ Select-ImageFile })
$Group.Controls.Add($BtnImg)

$ProjectLabel = New-Object System.Windows.Forms.Label
$ProjectLabel.Text = "项目目录"
$ProjectLabel.Location = New-Object System.Drawing.Point(20, 85)
$ProjectLabel.Size = New-Object System.Drawing.Size(80, 24)
$Group.Controls.Add($ProjectLabel)

$Script:ProjectDirText = New-Object System.Windows.Forms.TextBox
$Script:ProjectDirText.Location = New-Object System.Drawing.Point(100, 82)
$Script:ProjectDirText.Size = New-Object System.Drawing.Size(520, 26)
$Group.Controls.Add($Script:ProjectDirText)

$BtnProject = New-Object System.Windows.Forms.Button
$BtnProject.Text = "选择目录"
$BtnProject.Location = New-Object System.Drawing.Point(635, 80)
$BtnProject.Size = New-Object System.Drawing.Size(100, 30)
$BtnProject.Add_Click({ Select-ProjectDir })
$Group.Controls.Add($BtnProject)

$IconLabel = New-Object System.Windows.Forms.Label
$IconLabel.Text = "图标文件名"
$IconLabel.Location = New-Object System.Drawing.Point(20, 135)
$IconLabel.Size = New-Object System.Drawing.Size(80, 24)
$Group.Controls.Add($IconLabel)

$Script:IconNameText = New-Object System.Windows.Forms.TextBox
$Script:IconNameText.Location = New-Object System.Drawing.Point(100, 132)
$Script:IconNameText.Size = New-Object System.Drawing.Size(260, 26)
$Script:IconNameText.Text = "deepseek-agent-toolkit-v4-pro.ico"
$Group.Controls.Add($Script:IconNameText)

$BtnRun = New-Object System.Windows.Forms.Button
$BtnRun.Text = "一键生成并接入图标"
$BtnRun.Location = New-Object System.Drawing.Point(390, 125)
$BtnRun.Size = New-Object System.Drawing.Size(220, 42)
$BtnRun.BackColor = [System.Drawing.Color]::FromArgb(219,234,254)
$BtnRun.FlatStyle = "Flat"
$BtnRun.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$BtnRun.Add_Click({ Run-All })
$Group.Controls.Add($BtnRun)

$BtnOpenOut = New-Object System.Windows.Forms.Button
$BtnOpenOut.Text = "打开输出目录"
$BtnOpenOut.Location = New-Object System.Drawing.Point(625, 125)
$BtnOpenOut.Size = New-Object System.Drawing.Size(110, 42)
$BtnOpenOut.Add_Click({ Start-Process explorer.exe $Script:OutputDir })
$Group.Controls.Add($BtnOpenOut)

$LogGroup = New-Object System.Windows.Forms.GroupBox
$LogGroup.Text = "日志"
$LogGroup.Location = New-Object System.Drawing.Point(20, 325)
$LogGroup.Size = New-Object System.Drawing.Size(760, 170)
$LogGroup.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($LogGroup)

$Script:LogBox = New-Object System.Windows.Forms.TextBox
$Script:LogBox.Location = New-Object System.Drawing.Point(15, 25)
$Script:LogBox.Size = New-Object System.Drawing.Size(730, 125)
$Script:LogBox.Multiline = $true
$Script:LogBox.ScrollBars = "Vertical"
$Script:LogBox.ReadOnly = $true
$Script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(15,23,42)
$Script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(226,232,240)
$Script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$LogGroup.Controls.Add($Script:LogBox)

Add-Log "Universal Icon Toolkit GUI 修复版已启动。" "OK"
Add-Log "输出目录：$Script:OutputDir" "INFO"

$Form.Add_Shown({ $Form.Activate() })
[void][System.Windows.Forms.Application]::Run($Form)
