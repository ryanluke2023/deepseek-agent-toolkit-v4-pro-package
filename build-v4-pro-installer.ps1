# DeepSeek Agent Toolkit V4 Pro 安装包打包脚本
# 功能：
# 1. 使用 ps2exe 把 deepseek-agent-toolkit-v4-pro.ps1 打包成 EXE
# 2. 使用 Inno Setup 把 EXE 打包成 Windows 安装包
#
# 使用前准备：
# 1. 把 deepseek-agent-toolkit-v4-pro.ps1 放到本脚本同目录
# 2. 安装 Inno Setup：https://jrsoftware.org/isinfo.php
# 3. 执行：
#    powershell -ExecutionPolicy Bypass -File .\build-v4-pro-installer.ps1

$ErrorActionPreference = "Stop"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host " DeepSeek Agent Toolkit V4 Pro 安装包打包器" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourcePs1 = Join-Path $Root "deepseek-agent-toolkit-v4-pro.ps1"
$BuildDir = Join-Path $Root "build"
$DistDir = Join-Path $Root "dist"
$ExePath = Join-Path $BuildDir "DeepSeek-Agent-Toolkit-V4-Pro.exe"

$IconPath = Join-Path $Root "deepseek-agent-toolkit-v4-pro.ico"
$IssPath = Join-Path $Root "DeepSeek-Agent-Toolkit-V4-Pro.iss"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

if (-not (Test-Path $SourcePs1)) {
    throw "未找到源脚本：$SourcePs1"
}

Write-Host "[1/4] 检查 ps2exe..." -ForegroundColor Yellow

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "未检测到 ps2exe，正在安装到当前用户..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force
}

Write-Host "[2/4] 打包 PowerShell GUI 为 EXE..." -ForegroundColor Yellow

Invoke-ps2exe `
    -inputFile $SourcePs1 `
    -outputFile $ExePath `
    -title "DeepSeek Agent Toolkit V4 Pro" `
    -description "DeepSeek Agent Toolkit V4 Pro GUI Installer" `
    -company "DeepSeek Agent Toolkit" `
    -product "DeepSeek Agent Toolkit V4 Pro" `
    -copyright "Copyright 2026" `
    -version "4.0.0" `
    -iconFile $IconPath `r
    -noConsole `
    -STA

if (-not (Test-Path $ExePath)) {
    throw "EXE 打包失败：$ExePath"
}

Write-Host "[OK] EXE 已生成：$ExePath" -ForegroundColor Green

Write-Host "[3/4] 检查 Inno Setup..." -ForegroundColor Yellow

$PossibleISCC = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
)

$ISCC = $null

foreach ($p in $PossibleISCC) {
    if (Test-Path $p) {
        $ISCC = $p
        break
    }
}

if (-not $ISCC) {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $ISCC = $cmd.Source
    }
}

if (-not $ISCC) {
    Write-Host "未检测到 Inno Setup。" -ForegroundColor Red
    Write-Host "请先安装 Inno Setup：https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
    Write-Host "或者使用 winget 安装：" -ForegroundColor Yellow
    Write-Host "winget install JRSoftware.InnoSetup -e" -ForegroundColor Cyan
    throw "缺少 Inno Setup，无法继续生成安装包。"
}

Write-Host "[OK] Inno Setup：$ISCC" -ForegroundColor Green

Write-Host "[4/4] 生成安装包..." -ForegroundColor Yellow

& $ISCC $IssPath

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " 打包完成" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host "便携 EXE：" -ForegroundColor Cyan
Write-Host $ExePath
Write-Host ""
Write-Host "安装包目录：" -ForegroundColor Cyan
Write-Host $DistDir
Write-Host ""
Write-Host "如果成功，你会在 dist 目录看到：" -ForegroundColor Cyan
Write-Host "DeepSeek-Agent-Toolkit-V4-Pro-Setup.exe"
