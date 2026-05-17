# 图标接入说明

## 已生成图标

文件名：

`	ext
deepseek-agent-toolkit-v4-pro.ico
`

## 主程序 EXE 图标

ps2exe 打包脚本应包含：

`powershell
$IconPath = Join-Path $Root "deepseek-agent-toolkit-v4-pro.ico"

Invoke-ps2exe 
    -inputFile $SourcePs1 
    -outputFile $ExePath 
    -iconFile $IconPath 
    -noConsole 
    -STA
`

## 安装包图标

Inno Setup .iss 文件应包含：

`ini
[Setup]
SetupIconFile=deepseek-agent-toolkit-v4-pro.ico

[Files]
Source: "deepseek-agent-toolkit-v4-pro.ico"; DestDir: "{app}"; Flags: ignoreversion
`

## 如果图标没有马上显示

可以尝试：

1. 刷新文件夹
2. 改 EXE 文件名重新生成
3. 重启资源管理器
4. 重启电脑
