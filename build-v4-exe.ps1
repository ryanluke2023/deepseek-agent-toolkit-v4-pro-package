# DeepSeek Agent Toolkit V4 Pro EXE 打包脚本
# 使用：
# powershell -ExecutionPolicy Bypass -File .\build-v4-exe.ps1

$ErrorActionPreference = "Stop"

Write-Host "DeepSeek Agent Toolkit V4 Pro EXE 打包器" -ForegroundColor Cyan

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "未检测到 ps2exe，正在安装到 CurrentUser..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Source = Join-Path $ScriptDir "deepseek-agent-toolkit-v4-pro.ps1"
$Out = Join-Path $ScriptDir "DeepSeek-Agent-Toolkit-V4-Pro.exe"

if (-not (Test-Path $Source)) {
    throw "未找到源脚本：$Source"
}

Invoke-ps2exe `
    -inputFile $Source `
    -outputFile $Out `
    -title "DeepSeek Agent Toolkit V4 Pro" `
    -description "DeepSeek Agent Toolkit V4 Pro GUI Installer" `
    -company "DeepSeek Agent Toolkit" `
    -product "DeepSeek Agent Toolkit" `
    -version "4.0.0" `
    -noConsole `
    -STA

Write-Host "打包完成：$Out" -ForegroundColor Green
