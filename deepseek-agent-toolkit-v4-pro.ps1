#requires -Version 5.1
<#
DeepSeek Agent Toolkit V4 Pro GUI
目标：新人零思考 + 实用增强版
适用：Windows PowerShell 5.1+ / PowerShell 7+
界面：PowerShell WinForms，无需 Python / Electron / Tauri
编码：UTF-8 with BOM

V4 Pro 新增：
1. 环境健康评分
2. 一键恢复备份
3. 一键导出求助包 zip
4. 一键生成 CLAUDE.md
5. 一键选择项目目录并启动 Claude Code

启动：
powershell -ExecutionPolicy Bypass -File .\deepseek-agent-toolkit-v3.1-gui.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# =========================
# 全局路径
# =========================

$Script:ToolkitRoot = Join-Path ([Environment]::GetFolderPath("Desktop")) "DeepSeek-Agent-Toolkit-V4 Pro-GUI"
$Script:ConfigDir = Join-Path $Script:ToolkitRoot "config"
$Script:BackupDir = Join-Path $Script:ToolkitRoot "backups"
$Script:LogDir = Join-Path $Script:ToolkitRoot "logs"
$Script:ReportDir = Join-Path $Script:ToolkitRoot "reports"
$Script:HelpPackDir = Join-Path $Script:ToolkitRoot "help-packs"
$Script:ProjectsDir = Join-Path $Script:ToolkitRoot "projects"

foreach ($dir in @($Script:ToolkitRoot, $Script:ConfigDir, $Script:BackupDir, $Script:LogDir, $Script:ReportDir, $Script:HelpPackDir, $Script:ProjectsDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$Script:TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Script:LogPath = Join-Path $Script:LogDir "gui-$Script:TimeStamp.log"
$Script:ReportPath = Join-Path $Script:ReportDir "diagnostic-$Script:TimeStamp.txt"
$Script:EnvBackupPath = Join-Path $Script:BackupDir "env-backup-$Script:TimeStamp.json"
$Script:ClaudeSettingsBackupPath = Join-Path $Script:BackupDir "claude-settings-backup-$Script:TimeStamp.json"
$Script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)

# =========================
# 日志
# =========================

function Add-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "FAIL", "STEP")]
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

function Show-InfoBox {
    param([string]$Text, [string]$Title = "DeepSeek Agent Toolkit")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", "Information") | Out-Null
}

function Show-WarnBox {
    param([string]$Text, [string]$Title = "提示")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", "Warning") | Out-Null
}

function Show-ErrorBox {
    param([string]$Text, [string]$Title = "错误")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, "OK", "Error") | Out-Null
}

# =========================
# 工具函数
# =========================

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-EnvTarget {
    if ($Script:CurrentSessionCheck.Checked) {
        return "Process"
    }
    return "User"
}

function Get-EnvValue {
    param(
        [string]$Name,
        [ValidateSet("User", "Process")]
        [string]$Target = "User"
    )
    return [Environment]::GetEnvironmentVariable($Name, $Target)
}

function Set-EnvSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()][string]$Value,
        [ValidateSet("User", "Process")]
        [string]$Target = "User"
    )

    if ($Target -eq "Process") {
        if ($null -eq $Value) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable($Name, $null, "Process")
        } else {
            Set-Item -Path "Env:$Name" -Value $Value
            [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        }
        return
    }

    try {
        if ($null -eq $Value) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable($Name, $null, "User")
        } else {
            Set-Item -Path "Env:$Name" -Value $Value
            [Environment]::SetEnvironmentVariable($Name, $Value, "User")
        }
    } catch {
        Add-Log "写入 User 环境变量失败，自动改为当前会话 Process。原因：$($_.Exception.Message)" "WARN"
        if ($null -eq $Value) {
            Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
            [Environment]::SetEnvironmentVariable($Name, $null, "Process")
        } else {
            Set-Item -Path "Env:$Name" -Value $Value
            [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
        }
    }
}

function Mask-Secret {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    if ($Text.Length -le 10) {
        return "********"
    }

    return $Text.Substring(0, 6) + "..." + $Text.Substring($Text.Length - 4)
}

function Protect-TextSecrets {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $masked = $Text
    $masked = $masked -replace 'sk-[A-Za-z0-9_\-]{8,}', 'sk-***MASKED***'
    $masked = $masked -replace '(ANTHROPIC_AUTH_TOKEN\s*[=:]\s*)[^\r\n"]+', '$1***MASKED***'
    $masked = $masked -replace '(ANTHROPIC_API_KEY\s*[=:]\s*)[^\r\n"]+', '$1***MASKED***'
    $masked = $masked -replace '(OPENAI_API_KEY\s*[=:]\s*)[^\r\n"]+', '$1***MASKED***'
    $masked = $masked -replace '(DEEPSEEK_API_KEY\s*[=:]\s*)[^\r\n"]+', '$1***MASKED***'
    return $masked
}

function Get-ModelProfile {
    $mode = [string]$Script:ModelCombo.SelectedItem
    $profile = [ordered]@{}

    switch ($mode) {
        "快速省钱模式 - deepseek-v4-flash" {
            $profile.ClaudeMain = "deepseek-v4-flash"
            $profile.ClaudeSmall = "deepseek-v4-flash"
            $profile.OpenAIModel = "deepseek-chat"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
        "深度推理模式 - deepseek-reasoner" {
            $profile.ClaudeMain = "deepseek-v4-pro[1m]"
            $profile.ClaudeSmall = "deepseek-v4-flash"
            $profile.OpenAIModel = "deepseek-reasoner"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
        "通用聊天模式 - deepseek-chat" {
            $profile.ClaudeMain = "deepseek-v4-pro[1m]"
            $profile.ClaudeSmall = "deepseek-v4-flash"
            $profile.OpenAIModel = "deepseek-chat"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
        "自定义模型" {
            $claude = $Script:CustomClaudeText.Text.Trim()
            $openai = $Script:CustomOpenAIText.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($claude)) {
                $claude = "deepseek-v4-pro[1m]"
            }
            if ([string]::IsNullOrWhiteSpace($openai)) {
                $openai = "deepseek-chat"
            }

            $profile.ClaudeMain = $claude
            $profile.ClaudeSmall = $claude
            $profile.OpenAIModel = $openai
            $profile.ReasonerModel = "deepseek-reasoner"
        }
        default {
            $profile.ClaudeMain = "deepseek-v4-pro[1m]"
            $profile.ClaudeSmall = "deepseek-v4-flash"
            $profile.OpenAIModel = "deepseek-chat"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
    }

    return $profile
}

function Get-SelectedTools {
    $tools = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Script:ToolsCheckedList.CheckedItems) {
        $tools.Add([string]$item)
    }
    return $tools
}

function Validate-ApiKey {
    $apiKey = $Script:ApiKeyText.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Show-WarnBox "请先输入 DeepSeek API Key。"
        return $false
    }
    return $true
}

function Get-ProjectPath {
    return $Script:ProjectPathText.Text.Trim()
}

# =========================
# V3 核心功能
# =========================

function Backup-CurrentConfig {
    param([ValidateSet("User", "Process")][string]$Target)

    Add-Log "正在备份当前配置..." "STEP"

    $names = @(
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "CLAUDE_CODE_SUBAGENT_MODEL",
        "CLAUDE_CODE_EFFORT_LEVEL",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "DEEPSEEK_API_KEY",
        "DEEPSEEK_BASE_URL",
        "DEEPSEEK_MODEL",
        "DEEPSEEK_REASONER_MODEL",
        "HTTP_PROXY",
        "HTTPS_PROXY"
    )

    $backup = [ordered]@{
        Time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Scope = $Target
        Env = [ordered]@{}
    }

    foreach ($name in $names) {
        $backup.Env[$name] = Get-EnvValue -Name $name -Target $Target
    }

    [System.IO.File]::WriteAllText($Script:EnvBackupPath, ($backup | ConvertTo-Json -Depth 8), $Script:Utf8Bom)
    Add-Log "环境变量备份完成：$Script:EnvBackupPath" "OK"

    $claudeSettings = Join-Path (Join-Path $HOME ".claude") "settings.json"
    if (Test-Path $claudeSettings) {
        Copy-Item $claudeSettings $Script:ClaudeSettingsBackupPath -Force
        Add-Log "Claude settings.json 已备份：$Script:ClaudeSettingsBackupPath" "OK"
    }
}

function Repair-AuthConflict {
    param([ValidateSet("User", "Process")][string]$Target)

    Add-Log "正在修复 Auth conflict..." "STEP"

    $anthropicKey = Get-EnvValue -Name "ANTHROPIC_API_KEY" -Target $Target
    $anthropicToken = Get-EnvValue -Name "ANTHROPIC_AUTH_TOKEN" -Target $Target

    if (-not [string]::IsNullOrWhiteSpace($anthropicKey) -and -not [string]::IsNullOrWhiteSpace($anthropicToken)) {
        Add-Log "检测到 ANTHROPIC_API_KEY 与 ANTHROPIC_AUTH_TOKEN 同时存在。" "WARN"
        Set-EnvSafe -Name "ANTHROPIC_API_KEY" -Value $null -Target $Target
        Add-Log "已删除 ANTHROPIC_API_KEY，保留 ANTHROPIC_AUTH_TOKEN。" "OK"
    } elseif (-not [string]::IsNullOrWhiteSpace($anthropicKey)) {
        Add-Log "检测到 ANTHROPIC_API_KEY 残留，DeepSeek + Claude Code 推荐使用 ANTHROPIC_AUTH_TOKEN。" "WARN"
        Set-EnvSafe -Name "ANTHROPIC_API_KEY" -Value $null -Target $Target
        Add-Log "已删除 ANTHROPIC_API_KEY。" "OK"
    } else {
        Add-Log "未发现 Anthropic 认证冲突。" "OK"
    }
}

function Configure-Env {
    param(
        [string]$ApiKey,
        [ValidateSet("User", "Process")][string]$Target,
        [hashtable]$Profile,
        [System.Collections.Generic.List[string]]$Tools
    )

    Add-Log "开始配置环境变量，范围：$Target" "STEP"
    Repair-AuthConflict -Target $Target

    if ($Tools.Contains("Claude Code")) {
        Set-EnvSafe -Name "ANTHROPIC_API_KEY" -Value $null -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_BASE_URL" -Value "https://api.deepseek.com/anthropic" -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_AUTH_TOKEN" -Value $ApiKey -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_MODEL" -Value $Profile.ClaudeMain -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_DEFAULT_OPUS_MODEL" -Value $Profile.ClaudeMain -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_DEFAULT_SONNET_MODEL" -Value $Profile.ClaudeMain -Target $Target
        Set-EnvSafe -Name "ANTHROPIC_DEFAULT_HAIKU_MODEL" -Value $Profile.ClaudeSmall -Target $Target
        Set-EnvSafe -Name "CLAUDE_CODE_SUBAGENT_MODEL" -Value $Profile.ClaudeSmall -Target $Target
        Set-EnvSafe -Name "CLAUDE_CODE_EFFORT_LEVEL" -Value "max" -Target $Target
        Add-Log "Claude Code 环境变量已配置。" "OK"
    }

    $needOpenAI = $false
    foreach ($tool in $Tools) {
        if ($tool -ne "Claude Code") {
            $needOpenAI = $true
        }
    }

    if ($needOpenAI -or $Tools.Contains("OpenAI-Compatible 通用配置")) {
        Set-EnvSafe -Name "OPENAI_API_KEY" -Value $ApiKey -Target $Target
        Set-EnvSafe -Name "OPENAI_BASE_URL" -Value "https://api.deepseek.com" -Target $Target
        Set-EnvSafe -Name "DEEPSEEK_API_KEY" -Value $ApiKey -Target $Target
        Set-EnvSafe -Name "DEEPSEEK_BASE_URL" -Value "https://api.deepseek.com" -Target $Target
        Set-EnvSafe -Name "DEEPSEEK_MODEL" -Value $Profile.OpenAIModel -Target $Target
        Set-EnvSafe -Name "DEEPSEEK_REASONER_MODEL" -Value $Profile.ReasonerModel -Target $Target
        Add-Log "OpenAI-Compatible 通用环境变量已配置。" "OK"
    }
}

function Write-ClaudeSettings {
    param(
        [string]$ApiKey,
        [hashtable]$Profile
    )

    Add-Log "正在生成 ~/.claude/settings.json..." "STEP"

    $claudeDir = Join-Path $HOME ".claude"
    $settingsPath = Join-Path $claudeDir "settings.json"
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

    $settings = [ordered]@{
        env = [ordered]@{
            ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic"
            ANTHROPIC_AUTH_TOKEN = $ApiKey
            ANTHROPIC_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_OPUS_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_SONNET_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_HAIKU_MODEL = $Profile.ClaudeSmall
            CLAUDE_CODE_SUBAGENT_MODEL = $Profile.ClaudeSmall
            CLAUDE_CODE_EFFORT_LEVEL = "max"
        }
    }

    [System.IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 8), $Script:Utf8Bom)
    Add-Log "Claude settings.json 已生成：$settingsPath" "OK"

    $template = [ordered]@{
        env = [ordered]@{
            ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic"
            ANTHROPIC_AUTH_TOKEN = "你的 DeepSeek API Key"
            ANTHROPIC_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_OPUS_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_SONNET_MODEL = $Profile.ClaudeMain
            ANTHROPIC_DEFAULT_HAIKU_MODEL = $Profile.ClaudeSmall
            CLAUDE_CODE_SUBAGENT_MODEL = $Profile.ClaudeSmall
            CLAUDE_CODE_EFFORT_LEVEL = "max"
        }
    }

    [System.IO.File]::WriteAllText((Join-Path $Script:ConfigDir "claude-settings-template.json"), ($template | ConvertTo-Json -Depth 8), $Script:Utf8Bom)
}

function Write-AgentTemplates {
    param(
        [hashtable]$Profile,
        [System.Collections.Generic.List[string]]$Tools
    )

    Add-Log "正在生成 Agent 工具配置模板..." "STEP"

    $envTemplate = @"
# DeepSeek Agent 通用 .env 模板

# OpenAI-Compatible
OPENAI_API_KEY=你的 DeepSeek API Key
OPENAI_BASE_URL=https://api.deepseek.com

# DeepSeek
DEEPSEEK_API_KEY=你的 DeepSeek API Key
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=$($Profile.OpenAIModel)
DEEPSEEK_REASONER_MODEL=$($Profile.ReasonerModel)

# Claude Code / Anthropic-Compatible
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=你的 DeepSeek API Key
ANTHROPIC_MODEL=$($Profile.ClaudeMain)
ANTHROPIC_DEFAULT_OPUS_MODEL=$($Profile.ClaudeMain)
ANTHROPIC_DEFAULT_SONNET_MODEL=$($Profile.ClaudeMain)
ANTHROPIC_DEFAULT_HAIKU_MODEL=$($Profile.ClaudeSmall)
CLAUDE_CODE_SUBAGENT_MODEL=$($Profile.ClaudeSmall)
CLAUDE_CODE_EFFORT_LEVEL=max
"@

    $guide = @"
# DeepSeek Agent Toolkit V4 Pro GUI 配置说明

## 已选择工具

$($Tools -join "`r`n")

## Claude Code

Base URL:
https://api.deepseek.com/anthropic

Token:
DeepSeek API Key

主模型:
$($Profile.ClaudeMain)

子任务模型:
$($Profile.ClaudeSmall)

启动：
cd 你的项目目录
claude

## Cline / Roo Code / Kilo Code / Continue / OpenCode / 自研 Agent

选择：
OpenAI-Compatible / Custom OpenAI / OpenAI API Compatible

Base URL:
https://api.deepseek.com

API Key:
你的 DeepSeek API Key

Model:
$($Profile.OpenAIModel)

Reasoner:
$($Profile.ReasonerModel)

## V4 Pro 新功能

- 环境健康评分
- 一键恢复备份
- 一键导出求助包 zip
- 一键生成 CLAUDE.md
- 一键选择项目目录并启动 Claude Code
"@

    $continueConfig = @"
{
  "models": [
    {
      "title": "DeepSeek Chat",
      "provider": "openai",
      "model": "$($Profile.OpenAIModel)",
      "apiKey": "你的 DeepSeek API Key",
      "apiBase": "https://api.deepseek.com"
    },
    {
      "title": "DeepSeek Reasoner",
      "provider": "openai",
      "model": "$($Profile.ReasonerModel)",
      "apiKey": "你的 DeepSeek API Key",
      "apiBase": "https://api.deepseek.com"
    }
  ],
  "tabAutocompleteModel": {
    "title": "DeepSeek Fast",
    "provider": "openai",
    "model": "deepseek-chat",
    "apiKey": "你的 DeepSeek API Key",
    "apiBase": "https://api.deepseek.com"
  }
}
"@

    [System.IO.File]::WriteAllText((Join-Path $Script:ConfigDir ".env.deepseek.template"), $envTemplate, $Script:Utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $Script:ConfigDir "agent-config-guide.md"), $guide, $Script:Utf8Bom)
    [System.IO.File]::WriteAllText((Join-Path $Script:ConfigDir "continue-config-template.json"), $continueConfig, $Script:Utf8Bom)

    Add-Log "Agent 配置模板已生成：$Script:ConfigDir" "OK"
}

function Install-ClaudeCode {
    Add-Log "开始安装 / 更新 Claude Code..." "STEP"

    if (-not (Test-CommandExists "node")) {
        Add-Log "未检测到 Node.js。请先安装 Node.js 18+。" "FAIL"
        Show-WarnBox "未检测到 Node.js。请先安装 Node.js 18+，再安装 Claude Code。"
        return
    }

    if (-not (Test-CommandExists "npm")) {
        Add-Log "未检测到 npm。请检查 Node.js 是否安装完整。" "FAIL"
        Show-WarnBox "未检测到 npm。请检查 Node.js 是否安装完整。"
        return
    }

    try {
        Add-Log "Node.js：$(node --version)" "OK"
        Add-Log "npm：$(npm --version)" "OK"

        if (-not (Test-CommandExists "git")) {
            Add-Log "未检测到 Git。Windows 使用 Claude Code 通常建议安装 Git for Windows。" "WARN"
        } else {
            Add-Log "Git：$(git --version)" "OK"
        }

        Add-Log "正在执行：npm install -g @anthropic-ai/claude-code" "STEP"
        $output = npm install -g @anthropic-ai/claude-code 2>&1
        foreach ($line in $output) {
            Add-Log $line "INFO"
        }

        if (Test-CommandExists "claude") {
            Add-Log "Claude Code：$(claude --version)" "OK"
        } else {
            Add-Log "Claude Code 可能已安装，但当前终端 PATH 未刷新。请重新打开终端。" "WARN"
        }

        Update-HealthScore
        Show-InfoBox "Claude Code 安装 / 更新流程已完成。"
    } catch {
        Add-Log "安装 Claude Code 失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "安装 Claude Code 失败：$($_.Exception.Message)"
    }
}

function Test-DeepSeekApi {
    if (-not (Validate-ApiKey)) { return $false }

    $apiKey = $Script:ApiKeyText.Text.Trim()
    $profile = Get-ModelProfile

    Add-Log "正在测试 DeepSeek API，模型：$($profile.OpenAIModel)" "STEP"

    $body = @{
        model = $profile.OpenAIModel
        messages = @(
            @{
                role = "user"
                content = "请只回复 OK"
            }
        )
        max_tokens = 10
        stream = $false
    } | ConvertTo-Json -Depth 8

    try {
        $resp = Invoke-RestMethod `
            -Uri "https://api.deepseek.com/chat/completions" `
            -Method Post `
            -Headers @{
                "Authorization" = "Bearer $apiKey"
                "Content-Type" = "application/json"
            } `
            -Body $body `
            -TimeoutSec 30

        $content = $resp.choices[0].message.content
        Add-Log "DeepSeek API 测试成功，返回：$content" "OK"
        $Script:LastApiTestOk = $true
        Update-HealthScore
        Show-InfoBox "DeepSeek API 测试成功：$content"
        return $true
    } catch {
        Add-Log "DeepSeek API 测试失败：$($_.Exception.Message)" "FAIL"
        $Script:LastApiTestOk = $false
        Update-HealthScore
        Show-WarnBox "DeepSeek API 测试失败。可能原因：API Key 错误、余额不足、网络/代理问题、模型名不可用。`n`n$($_.Exception.Message)"
        return $false
    }
}

function Generate-DiagnosticReport {
    param(
        [ValidateSet("User", "Process")][string]$Target,
        [hashtable]$Profile,
        [System.Collections.Generic.List[string]]$Tools
    )

    Add-Log "正在生成诊断报告..." "STEP"

    $health = Get-HealthScoreData -Target $Target

    $envNames = @(
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "ANTHROPIC_MODEL",
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
        "CLAUDE_CODE_SUBAGENT_MODEL",
        "CLAUDE_CODE_EFFORT_LEVEL",
        "OPENAI_API_KEY",
        "OPENAI_BASE_URL",
        "DEEPSEEK_API_KEY",
        "DEEPSEEK_BASE_URL",
        "DEEPSEEK_MODEL",
        "DEEPSEEK_REASONER_MODEL",
        "HTTP_PROXY",
        "HTTPS_PROXY"
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("DeepSeek Agent Toolkit V4 Pro GUI 诊断报告")
    $lines.Add("生成时间：$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")")
    $lines.Add("写入范围：$Target")
    $lines.Add("")
    $lines.Add("一、环境健康评分")
    $lines.Add("总分：$($health.Score) / 100")
    foreach ($item in $health.Items) {
        $lines.Add($item)
    }
    $lines.Add("")
    $lines.Add("二、选择的 Agent 工具")
    foreach ($tool in $Tools) {
        $lines.Add("- $tool")
    }
    $lines.Add("")
    $lines.Add("三、模型配置")
    $lines.Add("Claude 主模型：$($Profile.ClaudeMain)")
    $lines.Add("Claude 子任务模型：$($Profile.ClaudeSmall)")
    $lines.Add("OpenAI-Compatible 模型：$($Profile.OpenAIModel)")
    $lines.Add("Reasoner 模型：$($Profile.ReasonerModel)")
    $lines.Add("")
    $lines.Add("四、命令检测")

    foreach ($cmd in @("node", "npm", "git", "claude")) {
        if (Test-CommandExists $cmd) {
            try {
                $ver = & $cmd --version 2>$null
                $lines.Add("[OK] $cmd：$ver")
            } catch {
                $lines.Add("[WARN] $cmd 存在，但版本检测失败")
            }
        } else {
            $lines.Add("[MISS] $cmd：未检测到")
        }
    }

    $lines.Add("")
    $lines.Add("五、环境变量")

    foreach ($name in $envNames) {
        $value = Get-EnvValue -Name $name -Target $Target
        if ($name -match "KEY|TOKEN") {
            $value = Mask-Secret $value
        }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $lines.Add("[EMPTY] $name=")
        } else {
            $lines.Add("[SET] $name=$value")
        }
    }

    $lines.Add("")
    $lines.Add("六、冲突判断")
    $anthropicKey = Get-EnvValue -Name "ANTHROPIC_API_KEY" -Target $Target
    $anthropicToken = Get-EnvValue -Name "ANTHROPIC_AUTH_TOKEN" -Target $Target

    if (-not [string]::IsNullOrWhiteSpace($anthropicKey) -and -not [string]::IsNullOrWhiteSpace($anthropicToken)) {
        $lines.Add("[FAIL] 同时存在 ANTHROPIC_API_KEY 和 ANTHROPIC_AUTH_TOKEN，可能导致 Auth conflict。")
    } else {
        $lines.Add("[OK] 未发现 Anthropic Auth conflict。")
    }

    $lines.Add("")
    $lines.Add("七、文件位置")
    $lines.Add("工具目录：$Script:ToolkitRoot")
    $lines.Add("日志文件：$Script:LogPath")
    $lines.Add("环境变量备份：$Script:EnvBackupPath")
    $lines.Add("Claude settings 备份：$Script:ClaudeSettingsBackupPath")
    $lines.Add("Claude settings 当前路径：$(Join-Path (Join-Path $HOME ".claude") "settings.json")")
    $lines.Add("")
    $lines.Add("八、下一步")
    $lines.Add("1. 重新打开 PowerShell / Windows Terminal")
    $lines.Add("2. 进入项目目录")
    $lines.Add("3. 执行 claude")
    $lines.Add("4. 其他 Agent 工具选择 OpenAI-Compatible，Base URL 填 https://api.deepseek.com")

    [System.IO.File]::WriteAllLines($Script:ReportPath, $lines, $Script:Utf8Bom)
    Add-Log "诊断报告已生成：$Script:ReportPath" "OK"
}

function Configure-All {
    if (-not (Validate-ApiKey)) { return }

    $apiKey = $Script:ApiKeyText.Text.Trim()
    $target = Get-EnvTarget
    $profile = Get-ModelProfile
    $tools = Get-SelectedTools

    if ($tools.Count -eq 0) {
        Show-WarnBox "请至少选择一个 Agent 工具。"
        return
    }

    try {
        Add-Log "========== 开始一键配置 ==========" "STEP"
        Add-Log "API Key：$(Mask-Secret $apiKey)" "INFO"
        Add-Log "写入范围：$target" "INFO"
        Add-Log "选择工具：$($tools -join ', ')" "INFO"

        Backup-CurrentConfig -Target $target
        Configure-Env -ApiKey $apiKey -Target $target -Profile $profile -Tools $tools

        if ($tools.Contains("Claude Code")) {
            Write-ClaudeSettings -ApiKey $apiKey -Profile $profile
        }

        Write-AgentTemplates -Profile $profile -Tools $tools
        Generate-DiagnosticReport -Target $target -Profile $profile -Tools $tools
        Update-HealthScore

        Add-Log "========== 一键配置完成 ==========" "OK"
        Show-InfoBox "配置完成！`n`n建议重新打开 PowerShell / Windows Terminal 后使用。`n`n诊断报告：$Script:ReportPath"
    } catch {
        Add-Log "一键配置失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "一键配置失败：$($_.Exception.Message)"
    }
}

function Uninstall-Config {
    $target = Get-EnvTarget

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "确定要卸载 DeepSeek Agent 环境变量配置吗？`n`n会先自动备份当前配置。",
        "确认卸载",
        "YesNo",
        "Warning"
    )

    if ($confirm -ne "Yes") {
        Add-Log "用户取消卸载。" "WARN"
        return
    }

    try {
        Add-Log "========== 开始卸载配置 ==========" "STEP"
        Backup-CurrentConfig -Target $target

        $names = @(
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_MODEL",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "CLAUDE_CODE_SUBAGENT_MODEL",
            "CLAUDE_CODE_EFFORT_LEVEL",
            "OPENAI_API_KEY",
            "OPENAI_BASE_URL",
            "DEEPSEEK_API_KEY",
            "DEEPSEEK_BASE_URL",
            "DEEPSEEK_MODEL",
            "DEEPSEEK_REASONER_MODEL"
        )

        foreach ($name in $names) {
            Set-EnvSafe -Name $name -Value $null -Target $target
        }

        Add-Log "DeepSeek Agent 环境变量已清理。" "OK"

        $settingsPath = Join-Path (Join-Path $HOME ".claude") "settings.json"
        if (Test-Path $settingsPath) {
            Copy-Item $settingsPath $Script:ClaudeSettingsBackupPath -Force
            Add-Log "已备份 Claude settings.json：$Script:ClaudeSettingsBackupPath" "OK"

            $deleteSettings = [System.Windows.Forms.MessageBox]::Show(
                "是否删除 ~/.claude/settings.json？`n`n选择 No 将保留该文件。",
                "删除 Claude settings.json？",
                "YesNo",
                "Question"
            )

            if ($deleteSettings -eq "Yes") {
                Remove-Item $settingsPath -Force
                Add-Log "已删除 ~/.claude/settings.json。" "OK"
            } else {
                Add-Log "已保留 ~/.claude/settings.json。" "WARN"
            }
        }

        $profile = Get-ModelProfile
        $tools = Get-SelectedTools
        Generate-DiagnosticReport -Target $target -Profile $profile -Tools $tools
        Update-HealthScore

        Add-Log "========== 卸载完成 ==========" "OK"
        Show-InfoBox "卸载完成。`n`n备份目录：$Script:BackupDir"
    } catch {
        Add-Log "卸载失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "卸载失败：$($_.Exception.Message)"
    }
}

function Export-LogAndOpenFolder {
    try {
        $target = Get-EnvTarget
        $profile = Get-ModelProfile
        $tools = Get-SelectedTools
        Generate-DiagnosticReport -Target $target -Profile $profile -Tools $tools

        Add-Log "日志文件：$Script:LogPath" "OK"
        Add-Log "诊断报告：$Script:ReportPath" "OK"

        Start-Process explorer.exe $Script:ToolkitRoot
    } catch {
        Show-ErrorBox "导出日志失败：$($_.Exception.Message)"
    }
}

function Detect-Environment {
    Add-Log "========== 开始环境检测 ==========" "STEP"

    foreach ($cmd in @("node", "npm", "git", "claude")) {
        if (Test-CommandExists $cmd) {
            try {
                $ver = & $cmd --version 2>$null
                Add-Log "$cmd：$ver" "OK"
            } catch {
                Add-Log "$cmd 存在，但版本检测失败。" "WARN"
            }
        } else {
            Add-Log "$cmd：未检测到" "WARN"
        }
    }

    $target = Get-EnvTarget
    $anthropicKey = Get-EnvValue -Name "ANTHROPIC_API_KEY" -Target $target
    $anthropicToken = Get-EnvValue -Name "ANTHROPIC_AUTH_TOKEN" -Target $target
    $baseUrl = Get-EnvValue -Name "ANTHROPIC_BASE_URL" -Target $target

    if (-not [string]::IsNullOrWhiteSpace($anthropicKey) -and -not [string]::IsNullOrWhiteSpace($anthropicToken)) {
        Add-Log "发现 Auth conflict：ANTHROPIC_API_KEY 和 ANTHROPIC_AUTH_TOKEN 同时存在。" "FAIL"
    } else {
        Add-Log "未发现 Anthropic Auth conflict。" "OK"
    }

    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        Add-Log "ANTHROPIC_BASE_URL 未设置。" "WARN"
    } else {
        Add-Log "ANTHROPIC_BASE_URL=$baseUrl" "OK"
    }

    Update-HealthScore
    Add-Log "========== 环境检测完成 ==========" "OK"
}

# =========================
# V4 Pro 新功能
# =========================

function Get-HealthScoreData {
    param([ValidateSet("User", "Process")][string]$Target)

    $score = 0
    $items = New-Object System.Collections.Generic.List[string]

    if (Test-CommandExists "node") {
        $score += 15
        $items.Add("[+15] Node.js 已安装")
    } else {
        $items.Add("[+0] Node.js 未安装")
    }

    if (Test-CommandExists "npm") {
        $score += 15
        $items.Add("[+15] npm 已安装")
    } else {
        $items.Add("[+0] npm 未安装")
    }

    if (Test-CommandExists "git") {
        $score += 10
        $items.Add("[+10] Git 已安装")
    } else {
        $items.Add("[+0] Git 未安装")
    }

    if (Test-CommandExists "claude") {
        $score += 20
        $items.Add("[+20] Claude Code 已安装")
    } else {
        $items.Add("[+0] Claude Code 未安装")
    }

    $anthropicBase = Get-EnvValue -Name "ANTHROPIC_BASE_URL" -Target $Target
    $anthropicToken = Get-EnvValue -Name "ANTHROPIC_AUTH_TOKEN" -Target $Target
    $openaiBase = Get-EnvValue -Name "OPENAI_BASE_URL" -Target $Target
    $deepseekKey = Get-EnvValue -Name "DEEPSEEK_API_KEY" -Target $Target
    $anthropicKey = Get-EnvValue -Name "ANTHROPIC_API_KEY" -Target $Target

    if ($anthropicBase -eq "https://api.deepseek.com/anthropic" -and -not [string]::IsNullOrWhiteSpace($anthropicToken)) {
        $score += 15
        $items.Add("[+15] Claude Code DeepSeek 配置正常")
    } else {
        $items.Add("[+0] Claude Code DeepSeek 配置不完整")
    }

    if ($openaiBase -eq "https://api.deepseek.com" -and -not [string]::IsNullOrWhiteSpace($deepseekKey)) {
        $score += 10
        $items.Add("[+10] OpenAI-Compatible DeepSeek 配置正常")
    } else {
        $items.Add("[+0] OpenAI-Compatible DeepSeek 配置不完整")
    }

    if (-not [string]::IsNullOrWhiteSpace($anthropicKey) -and -not [string]::IsNullOrWhiteSpace($anthropicToken)) {
        $items.Add("[-10] 存在 Auth conflict")
        $score -= 10
    } else {
        $score += 10
        $items.Add("[+10] 无 Auth conflict")
    }

    if ($Script:LastApiTestOk -eq $true) {
        $score += 5
        $items.Add("[+5] 最近一次 API 测试成功")
    } elseif ($Script:LastApiTestOk -eq $false) {
        $items.Add("[+0] 最近一次 API 测试失败")
    } else {
        $items.Add("[+0] 尚未进行 API 测试")
    }

    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }

    return [ordered]@{
        Score = $score
        Items = $items
    }
}

function Update-HealthScore {
    try {
        $target = Get-EnvTarget
        $data = Get-HealthScoreData -Target $target
        $score = [int]$data.Score

        $Script:HealthScoreLabel.Text = "环境健康评分：$score / 100"
        $Script:HealthBar.Value = [Math]::Min([Math]::Max($score, 0), 100)

        if ($score -ge 85) {
            $Script:HealthStatusLabel.Text = "状态：优秀，可以正常使用"
            $Script:HealthStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
        } elseif ($score -ge 65) {
            $Script:HealthStatusLabel.Text = "状态：基本可用，建议检查黄色项"
            $Script:HealthStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(202, 138, 4)
        } else {
            $Script:HealthStatusLabel.Text = "状态：需要修复，建议先检测环境"
            $Script:HealthStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
        }

        $Script:HealthDetailBox.Text = ($data.Items -join "`r`n")
    } catch {
        Add-Log "更新健康评分失败：$($_.Exception.Message)" "WARN"
    }
}

function Restore-Backup {
    try {
        $files = Get-ChildItem -Path $Script:BackupDir -Filter "env-backup-*.json" -File | Sort-Object LastWriteTime -Descending

        if (-not $files -or $files.Count -eq 0) {
            Show-WarnBox "没有找到可恢复的环境变量备份。"
            return
        }

        $picker = New-Object System.Windows.Forms.Form
        $picker.Text = "选择要恢复的备份"
        $picker.Size = New-Object System.Drawing.Size(650, 420)
        $picker.StartPosition = "CenterParent"
        $picker.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = "请选择一个环境变量备份文件："
        $label.Location = New-Object System.Drawing.Point(20, 20)
        $label.Size = New-Object System.Drawing.Size(580, 24)
        $picker.Controls.Add($label)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Location = New-Object System.Drawing.Point(20, 55)
        $list.Size = New-Object System.Drawing.Size(590, 240)
        foreach ($f in $files) {
            [void]$list.Items.Add($f.FullName)
        }
        $list.SelectedIndex = 0
        $picker.Controls.Add($list)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = "恢复选中备份"
        $ok.Location = New-Object System.Drawing.Point(320, 315)
        $ok.Size = New-Object System.Drawing.Size(140, 36)
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $picker.Controls.Add($ok)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = "取消"
        $cancel.Location = New-Object System.Drawing.Point(470, 315)
        $cancel.Size = New-Object System.Drawing.Size(140, 36)
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $picker.Controls.Add($cancel)

        $picker.AcceptButton = $ok
        $picker.CancelButton = $cancel

        $result = $picker.ShowDialog($Form)
        if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
            Add-Log "用户取消恢复备份。" "WARN"
            return
        }

        $selected = [string]$list.SelectedItem
        if ([string]::IsNullOrWhiteSpace($selected)) { return }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "确定恢复此备份吗？`n`n$selected`n`n当前配置会先自动备份。",
            "确认恢复",
            "YesNo",
            "Warning"
        )

        if ($confirm -ne "Yes") { return }

        $target = Get-EnvTarget
        Backup-CurrentConfig -Target $target

        $json = Get-Content -Raw -LiteralPath $selected -Encoding UTF8 | ConvertFrom-Json
        $envObj = $json.Env

        foreach ($prop in $envObj.PSObject.Properties) {
            $name = $prop.Name
            $value = $prop.Value
            if ([string]::IsNullOrWhiteSpace([string]$value)) {
                Set-EnvSafe -Name $name -Value $null -Target $target
            } else {
                Set-EnvSafe -Name $name -Value ([string]$value) -Target $target
            }
        }

        Add-Log "环境变量备份已恢复：$selected" "OK"

        # 可选恢复最近的 claude settings 备份
        $settingsBackups = Get-ChildItem -Path $Script:BackupDir -Filter "claude-settings-backup-*.json" -File | Sort-Object LastWriteTime -Descending
        if ($settingsBackups -and $settingsBackups.Count -gt 0) {
            $restoreSettings = [System.Windows.Forms.MessageBox]::Show(
                "是否同时恢复最近的 Claude settings.json 备份？",
                "恢复 Claude settings.json？",
                "YesNo",
                "Question"
            )

            if ($restoreSettings -eq "Yes") {
                $claudeDir = Join-Path $HOME ".claude"
                New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
                Copy-Item $settingsBackups[0].FullName (Join-Path $claudeDir "settings.json") -Force
                Add-Log "Claude settings.json 已恢复：$($settingsBackups[0].FullName)" "OK"
            }
        }

        Update-HealthScore
        Show-InfoBox "备份恢复完成。建议重新打开 PowerShell / Windows Terminal。"
    } catch {
        Add-Log "恢复备份失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "恢复备份失败：$($_.Exception.Message)"
    }
}

function Export-HelpPackZip {
    try {
        Add-Log "正在生成求助包 zip..." "STEP"

        $target = Get-EnvTarget
        $profile = Get-ModelProfile
        $tools = Get-SelectedTools
        Generate-DiagnosticReport -Target $target -Profile $profile -Tools $tools

        $packTime = Get-Date -Format "yyyyMMdd-HHmmss"
        $tempDir = Join-Path $Script:HelpPackDir "DeepSeek-Agent-HelpPack-$packTime"
        $zipPath = Join-Path $Script:HelpPackDir "DeepSeek-Agent-HelpPack-$packTime.zip"

        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

        # masked diagnostic
        $diagText = Get-Content -Raw -LiteralPath $Script:ReportPath -Encoding UTF8
        [System.IO.File]::WriteAllText((Join-Path $tempDir "diagnostic-masked.txt"), (Protect-TextSecrets $diagText), $Script:Utf8Bom)

        # masked log
        if (Test-Path $Script:LogPath) {
            $logText = Get-Content -Raw -LiteralPath $Script:LogPath -Encoding UTF8
            [System.IO.File]::WriteAllText((Join-Path $tempDir "install-log-masked.txt"), (Protect-TextSecrets $logText), $Script:Utf8Bom)
        }

        # masked env current
        $envNames = @(
            "ANTHROPIC_API_KEY",
            "ANTHROPIC_AUTH_TOKEN",
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_MODEL",
            "OPENAI_API_KEY",
            "OPENAI_BASE_URL",
            "DEEPSEEK_API_KEY",
            "DEEPSEEK_BASE_URL",
            "DEEPSEEK_MODEL",
            "DEEPSEEK_REASONER_MODEL",
            "HTTP_PROXY",
            "HTTPS_PROXY"
        )

        $envMasked = [ordered]@{
            Time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Scope = $target
            Env = [ordered]@{}
        }

        foreach ($name in $envNames) {
            $value = Get-EnvValue -Name $name -Target $target
            if ($name -match "KEY|TOKEN") {
                $value = Mask-Secret $value
            }
            $envMasked.Env[$name] = $value
        }

        [System.IO.File]::WriteAllText((Join-Path $tempDir "env-masked.json"), ($envMasked | ConvertTo-Json -Depth 8), $Script:Utf8Bom)

        # masked claude settings
        $settingsPath = Join-Path (Join-Path $HOME ".claude") "settings.json"
        if (Test-Path $settingsPath) {
            $settingsText = Get-Content -Raw -LiteralPath $settingsPath -Encoding UTF8
            [System.IO.File]::WriteAllText((Join-Path $tempDir "claude-settings-masked.json"), (Protect-TextSecrets $settingsText), $Script:Utf8Bom)
        }

        # system info
        $sysInfo = @"
DeepSeek Agent HelpPack

生成时间：$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Windows 用户：$env:USERNAME
电脑名：$env:COMPUTERNAME
PowerShell 版本：$($PSVersionTable.PSVersion)
系统版本：$([Environment]::OSVersion.VersionString)
工具目录：$Script:ToolkitRoot

命令检测：
node: $(if (Test-CommandExists "node") { node --version } else { "未检测到" })
npm: $(if (Test-CommandExists "npm") { npm --version } else { "未检测到" })
git: $(if (Test-CommandExists "git") { git --version } else { "未检测到" })
claude: $(if (Test-CommandExists "claude") { claude --version } else { "未检测到" })
"@
        [System.IO.File]::WriteAllText((Join-Path $tempDir "system-info.txt"), $sysInfo, $Script:Utf8Bom)

        $readme = @"
# DeepSeek Agent 求助包

这个 zip 已自动脱敏，适合发给他人排查问题。

包含：
- diagnostic-masked.txt：诊断报告
- install-log-masked.txt：安装/运行日志
- env-masked.json：脱敏后的环境变量
- claude-settings-masked.json：脱敏后的 Claude 配置
- system-info.txt：系统信息

注意：
如果你手动添加了其他敏感信息，请先检查再发送。
"@
        [System.IO.File]::WriteAllText((Join-Path $tempDir "README.md"), $readme, $Script:Utf8Bom)

        if (Test-Path $zipPath) {
            Remove-Item $zipPath -Force
        }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath)
        Remove-Item $tempDir -Recurse -Force

        Add-Log "求助包已生成：$zipPath" "OK"
        Show-InfoBox "求助包已生成：`n`n$zipPath"
        Start-Process explorer.exe $Script:HelpPackDir
    } catch {
        Add-Log "生成求助包失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "生成求助包失败：$($_.Exception.Message)"
    }
}

function Select-ProjectFolder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "请选择要使用 Claude Code 的项目目录"
    $dialog.ShowNewFolderButton = $true

    if (-not [string]::IsNullOrWhiteSpace($Script:ProjectPathText.Text) -and (Test-Path $Script:ProjectPathText.Text)) {
        $dialog.SelectedPath = $Script:ProjectPathText.Text
    }

    $result = $dialog.ShowDialog($Form)
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $Script:ProjectPathText.Text = $dialog.SelectedPath
        Add-Log "已选择项目目录：$($dialog.SelectedPath)" "OK"
    }
}

function Generate-ClaudeMd {
    try {
        $projectPath = Get-ProjectPath
        if ([string]::IsNullOrWhiteSpace($projectPath)) {
            Show-WarnBox "请先选择项目目录。"
            return
        }

        if (-not (Test-Path $projectPath)) {
            New-Item -ItemType Directory -Force -Path $projectPath | Out-Null
        }

        $projectName = Split-Path $projectPath -Leaf
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            $projectName = "My Project"
        }

        $techStack = $Script:TechStackText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($techStack)) {
            $techStack = "请根据项目文件自动识别技术栈。"
        }

        $projectGoal = $Script:ProjectGoalText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($projectGoal)) {
            $projectGoal = "请帮助我高质量完成项目开发、调试、重构、测试和文档生成。"
        }

        $claudePath = Join-Path $projectPath "CLAUDE.md"

        if (Test-Path $claudePath) {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "CLAUDE.md 已存在，是否覆盖？`n`n覆盖前会自动备份。",
                "确认覆盖",
                "YesNo",
                "Warning"
            )

            if ($confirm -ne "Yes") {
                Add-Log "用户取消生成 CLAUDE.md。" "WARN"
                return
            }

            $backupPath = Join-Path $Script:BackupDir ("CLAUDE-backup-$Script:TimeStamp.md")
            Copy-Item $claudePath $backupPath -Force
            Add-Log "旧 CLAUDE.md 已备份：$backupPath" "OK"
        }

        $content = @"
# CLAUDE.md

## 项目名称

$projectName

## 项目目标

$projectGoal

## 技术栈

$techStack

## Claude Code 工作方式

请你作为资深全栈工程师、系统架构师和代码审查助手协助开发本项目。

工作原则：

1. 先阅读项目结构，再修改代码。
2. 修改前先说明计划。
3. 尽量小步修改，避免一次性大范围破坏。
4. 修改后说明改了哪些文件、为什么改、如何测试。
5. 对关键逻辑添加必要注释。
6. 不要删除用户已有重要代码，除非明确说明原因。
7. 发现安全问题、依赖问题、编码问题时主动提醒。
8. Windows 环境下脚本优先兼容 PowerShell。
9. 中文输出时保持清晰、简洁、适合新人理解。
10. 如果涉及 Tailwind，请优先使用 Tailwind CSS v4 思路。

## 常用命令

请根据项目实际情况自动识别并补充：

```bash
npm install
npm run dev
npm run build
npm run test
```

如果项目不是 Node.js，请根据项目技术栈调整命令。

## 目录规范建议

```text
/src        主源码
/components 组件
/lib        工具函数
/config     配置
/scripts    脚本
/docs       文档
/tests      测试
/prompts    Prompt 模板
```

## 代码规范

- 保持文件结构清晰。
- 命名要有意义。
- 函数尽量短小，职责单一。
- 错误处理要明确。
- 不要硬编码 API Key、Token、密码。
- `.env` 只保存本地密钥，提交仓库时使用 `.env.example`。
- 输出代码时请优先给可直接运行的完整版本。

## 安全要求

禁止把以下内容写入日志、README、提交记录或前端页面：

- API Key
- Token
- 私钥
- Cookie
- 账号密码
- 个人敏感信息

## Agent 协作要求

当我说：

- “规划”：请输出任务拆解和文件结构。
- “开发”：请直接修改/生成代码。
- “测试”：请设计测试步骤并指出可能失败点。
- “修复”：请定位问题、解释原因、给出修复方案。
- “打包”：请生成可发布版本和使用说明。
- “做成新人版”：请把说明写得更简单、更适合零基础用户。

## DeepSeek Agent 配置备注

本项目可能使用 DeepSeek API 接入 Claude Code。

Claude Code Anthropic-Compatible Base URL：

```text
https://api.deepseek.com/anthropic
```

OpenAI-Compatible Base URL：

```text
https://api.deepseek.com
```

请不要在项目文件中明文写入真实 API Key。

## 输出偏好

- 中文说明要清楚。
- 关键步骤给命令。
- 遇到 Windows PowerShell 编码问题，优先使用 UTF-8 with BOM。
- 对新人容易出错的地方，要提前提醒。
"@

        [System.IO.File]::WriteAllText($claudePath, $content, $Script:Utf8Bom)
        Add-Log "CLAUDE.md 已生成：$claudePath" "OK"
        Show-InfoBox "CLAUDE.md 已生成：`n`n$claudePath"
    } catch {
        Add-Log "生成 CLAUDE.md 失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "生成 CLAUDE.md 失败：$($_.Exception.Message)"
    }
}

function Launch-ClaudeCodeInProject {
    try {
        $projectPath = Get-ProjectPath
        if ([string]::IsNullOrWhiteSpace($projectPath)) {
            Show-WarnBox "请先选择项目目录。"
            return
        }

        if (-not (Test-Path $projectPath)) {
            Show-WarnBox "项目目录不存在：$projectPath"
            return
        }

        if (-not (Test-CommandExists "claude")) {
            Show-WarnBox "未检测到 claude 命令。请先点击“一键安装 Claude Code”，安装后重新打开终端。"
            return
        }

        Add-Log "准备在项目目录启动 Claude Code：$projectPath" "STEP"

        $psCommand = "cd `"$projectPath`"; claude"
        Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", $psCommand

        Add-Log "已启动新的 PowerShell 窗口并执行 claude。" "OK"
    } catch {
        Add-Log "启动 Claude Code 失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "启动 Claude Code 失败：$($_.Exception.Message)"
    }
}


# =========================
# V4 Pro 新功能
# =========================

function Get-V4ProviderProfile {
    $name = [string]$Script:ProviderCombo.SelectedItem
    $profile = [ordered]@{}

    switch ($name) {
        "DeepSeek 官方" {
            $profile.Name = "DeepSeek"
            $profile.BaseUrl = "https://api.deepseek.com"
            $profile.AnthropicUrl = "https://api.deepseek.com/anthropic"
            $profile.DefaultModel = "deepseek-chat"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
        "OpenRouter" {
            $profile.Name = "OpenRouter"
            $profile.BaseUrl = "https://openrouter.ai/api/v1"
            $profile.AnthropicUrl = ""
            $profile.DefaultModel = "deepseek/deepseek-chat"
            $profile.ReasonerModel = "deepseek/deepseek-r1"
        }
        "OpenAI 官方" {
            $profile.Name = "OpenAI"
            $profile.BaseUrl = "https://api.openai.com/v1"
            $profile.AnthropicUrl = ""
            $profile.DefaultModel = "gpt-4.1"
            $profile.ReasonerModel = "o3"
        }
        "Anthropic 官方" {
            $profile.Name = "Anthropic"
            $profile.BaseUrl = ""
            $profile.AnthropicUrl = "https://api.anthropic.com"
            $profile.DefaultModel = "claude-sonnet-4-5"
            $profile.ReasonerModel = "claude-opus-4-1"
        }
        "SiliconFlow 硅基流动" {
            $profile.Name = "SiliconFlow"
            $profile.BaseUrl = "https://api.siliconflow.cn/v1"
            $profile.AnthropicUrl = ""
            $profile.DefaultModel = "deepseek-ai/DeepSeek-V3"
            $profile.ReasonerModel = "deepseek-ai/DeepSeek-R1"
        }
        "Ollama 本地" {
            $profile.Name = "Ollama"
            $profile.BaseUrl = "http://localhost:11434/v1"
            $profile.AnthropicUrl = ""
            $profile.DefaultModel = "qwen2.5-coder"
            $profile.ReasonerModel = "deepseek-r1"
        }
        "LM Studio 本地" {
            $profile.Name = "LM Studio"
            $profile.BaseUrl = "http://localhost:1234/v1"
            $profile.AnthropicUrl = ""
            $profile.DefaultModel = "local-model"
            $profile.ReasonerModel = "local-model"
        }
        default {
            $profile.Name = "DeepSeek"
            $profile.BaseUrl = "https://api.deepseek.com"
            $profile.AnthropicUrl = "https://api.deepseek.com/anthropic"
            $profile.DefaultModel = "deepseek-chat"
            $profile.ReasonerModel = "deepseek-reasoner"
        }
    }

    return $profile
}

function Apply-V4ProviderDefaults {
    try {
        $p = Get-V4ProviderProfile
        $Script:ProviderBaseUrlText.Text = $p.BaseUrl
        $Script:CustomOpenAIText.Text = $p.DefaultModel
        Add-Log "已切换 Provider：$($p.Name)，Base URL：$($p.BaseUrl)，默认模型：$($p.DefaultModel)" "OK"
    } catch {
        Add-Log "切换 Provider 失败：$($_.Exception.Message)" "WARN"
    }
}

function Save-V4EncryptedApiKey {
    try {
        $key = $Script:ApiKeyText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            Show-WarnBox "请先输入 API Key。"
            return
        }

        $provider = Get-V4ProviderProfile
        $secure = ConvertTo-SecureString $key -AsPlainText -Force
        $encrypted = ConvertFrom-SecureString $secure

        $store = [ordered]@{
            Time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Provider = $provider.Name
            BaseUrl = $provider.BaseUrl
            ApiKeyEncrypted = $encrypted
            Note = "此文件使用 Windows DPAPI 加密，通常只能由当前 Windows 用户在当前电脑解密。"
        }

        $keyStorePath = Join-Path $Script:ConfigDir "v4-provider-key.encrypted.json"
        [System.IO.File]::WriteAllText($keyStorePath, ($store | ConvertTo-Json -Depth 8), $Script:Utf8Bom)
        Add-Log "API Key 已加密保存：$keyStorePath" "OK"
        Show-InfoBox "API Key 已加密保存。`n`n$keyStorePath"
    } catch {
        Add-Log "加密保存 API Key 失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "加密保存 API Key 失败：$($_.Exception.Message)"
    }
}

function Load-V4EncryptedApiKey {
    try {
        $keyStorePath = Join-Path $Script:ConfigDir "v4-provider-key.encrypted.json"
        if (-not (Test-Path $keyStorePath)) {
            Show-WarnBox "没有找到已加密保存的 API Key。"
            return
        }

        $store = Get-Content -Raw -LiteralPath $keyStorePath -Encoding UTF8 | ConvertFrom-Json
        $secure = ConvertTo-SecureString $store.ApiKeyEncrypted
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }

        $Script:ApiKeyText.Text = $plain
        Add-Log "已从加密文件读取 API Key，Provider：$($store.Provider)" "OK"
        Show-InfoBox "API Key 已读取到输入框。"
    } catch {
        Add-Log "读取加密 API Key 失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "读取加密 API Key 失败：$($_.Exception.Message)"
    }
}

function Test-V4ModelSpeed {
    try {
        $apiKey = $Script:ApiKeyText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($apiKey)) {
            Show-WarnBox "请先输入 API Key。Ollama / LM Studio 如未配置鉴权，可输入任意占位符。"
            return
        }

        $provider = Get-V4ProviderProfile
        $baseUrl = $Script:ProviderBaseUrlText.Text.Trim()
        $model = $Script:CustomOpenAIText.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($baseUrl)) {
            Show-WarnBox "当前 Provider 没有 OpenAI-Compatible Base URL，无法执行这个测速。"
            return
        }

        if ([string]::IsNullOrWhiteSpace($model)) {
            Show-WarnBox "请填写要测速的 OpenAI-Compatible 模型。"
            return
        }

        Add-Log "开始模型测速：Provider=$($provider.Name)，Model=$model，Base URL=$baseUrl" "STEP"

        $url = $baseUrl.TrimEnd("/") + "/chat/completions"
        $body = @{
            model = $model
            messages = @(
                @{
                    role = "user"
                    content = "请用一句中文回复：测速成功。"
                }
            )
            max_tokens = 32
            stream = $false
        } | ConvertTo-Json -Depth 8

        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $headers = @{
            "Content-Type" = "application/json"
        }

        # 本地服务有时不需要真实 Key，但 OpenAI-compatible 通常接受 Bearer 占位符
        if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
            $headers["Authorization"] = "Bearer $apiKey"
        }

        $resp = Invoke-RestMethod `
            -Uri $url `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -TimeoutSec 60

        $sw.Stop()

        $content = $resp.choices[0].message.content
        $ms = [int]$sw.ElapsedMilliseconds

        $speedText = "Provider: $($provider.Name)`r`nModel: $model`r`n耗时: $ms ms`r`n返回: $content"
        $speedPath = Join-Path $Script:ReportDir ("model-speed-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
        [System.IO.File]::WriteAllText($speedPath, $speedText, $Script:Utf8Bom)

        Add-Log "模型测速成功：$ms ms，返回：$content" "OK"
        Show-InfoBox "模型测速成功！`n`n耗时：$ms ms`n返回：$content"
    } catch {
        Add-Log "模型测速失败：$($_.Exception.Message)" "FAIL"
        Show-WarnBox "模型测速失败：`n`n$($_.Exception.Message)"
    }
}

function Install-V4NodeGitWithWinget {
    try {
        if (-not (Test-CommandExists "winget")) {
            Show-WarnBox "未检测到 winget。请先安装或更新 App Installer。"
            Add-Log "未检测到 winget，无法自动安装 Node.js / Git。" "WARN"
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "将使用 winget 安装 / 更新 Node.js LTS 和 Git for Windows。`n`n是否继续？",
            "确认安装依赖",
            "YesNo",
            "Question"
        )

        if ($confirm -ne "Yes") {
            Add-Log "用户取消 winget 依赖安装。" "WARN"
            return
        }

        Add-Log "开始使用 winget 安装 / 更新 Node.js LTS..." "STEP"
        Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements; winget install Git.Git -e --accept-source-agreements --accept-package-agreements; Write-Host '安装完成后请重新打开 DeepSeek Agent Toolkit V4 Pro。' -ForegroundColor Green"
        Show-InfoBox "已打开新的 PowerShell 窗口执行 winget 安装。安装完成后请重新打开本工具。"
    } catch {
        Add-Log "winget 安装依赖失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "winget 安装依赖失败：$($_.Exception.Message)"
    }
}

function Generate-V4ReleaseFiles {
    try {
        Add-Log "正在生成 V4 Pro 发布文件..." "STEP"

        $releaseDir = Join-Path $Script:ToolkitRoot "release"
        New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

        $buildScript = @'
# DeepSeek Agent Toolkit V4 Pro EXE 打包脚本
# 用法：
# powershell -ExecutionPolicy Bypass -File .\build-v4-exe.ps1

$ErrorActionPreference = "Stop"

Write-Host "DeepSeek Agent Toolkit V4 Pro EXE 打包器" -ForegroundColor Cyan

if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "未检测到 ps2exe，正在安装..." -ForegroundColor Yellow
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
'@

        $releaseReadme = @'
# DeepSeek Agent Toolkit V4 Pro 发布说明

## 运行脚本版

```powershell
powershell -ExecutionPolicy Bypass -File .\deepseek-agent-toolkit-v4-pro.ps1
```

## 打包 EXE

```powershell
powershell -ExecutionPolicy Bypass -File .\build-v4-exe.ps1
```

打包需要联网安装 `ps2exe` PowerShell 模块。

## V4 Pro 新增

- Provider 管理
- API Key DPAPI 加密保存 / 读取
- OpenAI-Compatible 模型测速
- winget 一键安装 Node.js LTS / Git
- 生成 EXE 打包脚本
- 保留 V3.1 全部能力
'@

        $currentScriptPath = $PSCommandPath
        if ([string]::IsNullOrWhiteSpace($currentScriptPath) -or -not (Test-Path $currentScriptPath)) {
            Add-Log "无法自动复制当前脚本，可能是在交互环境运行。" "WARN"
        } else {
            Copy-Item $currentScriptPath (Join-Path $releaseDir "deepseek-agent-toolkit-v4-pro.ps1") -Force
        }

        [System.IO.File]::WriteAllText((Join-Path $releaseDir "build-v4-exe.ps1"), $buildScript, $Script:Utf8Bom)
        [System.IO.File]::WriteAllText((Join-Path $releaseDir "README-V4-Pro.md"), $releaseReadme, $Script:Utf8Bom)

        Add-Log "V4 Pro 发布文件已生成：$releaseDir" "OK"
        Show-InfoBox "V4 Pro 发布文件已生成：`n`n$releaseDir"
        Start-Process explorer.exe $releaseDir
    } catch {
        Add-Log "生成发布文件失败：$($_.Exception.Message)" "FAIL"
        Show-ErrorBox "生成发布文件失败：$($_.Exception.Message)"
    }
}

# =========================
# GUI
# =========================

[System.Windows.Forms.Application]::EnableVisualStyles()

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "DeepSeek Agent Toolkit V4 Pro GUI - 产品化增强版"
$Form.Size = New-Object System.Drawing.Size(1180, 900)
$Form.StartPosition = "CenterScreen"
$Form.MinimumSize = New-Object System.Drawing.Size(1180, 900)
$Form.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)

$fontMain = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$fontTitle = New-Object System.Drawing.Font("Microsoft YaHei UI", 16, [System.Drawing.FontStyle]::Bold)
$fontSub = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

$Form.Font = $fontMain

# 标题
$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "DeepSeek Agent Toolkit V4 Pro GUI"
$TitleLabel.Font = $fontTitle
$TitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$TitleLabel.Location = New-Object System.Drawing.Point(20, 14)
$TitleLabel.Size = New-Object System.Drawing.Size(650, 32)
$Form.Controls.Add($TitleLabel)

$SubLabel = New-Object System.Windows.Forms.Label
$SubLabel.Text = "Provider 管理 · API Key 加密保存 · 模型测速 · winget 依赖安装 · EXE 打包"
$SubLabel.Font = $fontSub
$SubLabel.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$SubLabel.Location = New-Object System.Drawing.Point(22, 50)
$SubLabel.Size = New-Object System.Drawing.Size(1000, 24)
$Form.Controls.Add($SubLabel)

# 左侧配置面板
$Panel = New-Object System.Windows.Forms.GroupBox
$Panel.Text = "配置区"
$Panel.Location = New-Object System.Drawing.Point(20, 82)
$Panel.Size = New-Object System.Drawing.Size(420, 405)
$Panel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($Panel)

$ApiKeyLabel = New-Object System.Windows.Forms.Label
$ApiKeyLabel.Text = "DeepSeek API Key"
$ApiKeyLabel.Location = New-Object System.Drawing.Point(18, 30)
$ApiKeyLabel.Size = New-Object System.Drawing.Size(180, 22)
$Panel.Controls.Add($ApiKeyLabel)

$Script:ApiKeyText = New-Object System.Windows.Forms.TextBox
$Script:ApiKeyText.Location = New-Object System.Drawing.Point(18, 55)
$Script:ApiKeyText.Size = New-Object System.Drawing.Size(310, 26)
$Script:ApiKeyText.UseSystemPasswordChar = $true
$Panel.Controls.Add($Script:ApiKeyText)

$ShowKeyCheck = New-Object System.Windows.Forms.CheckBox
$ShowKeyCheck.Text = "显示"
$ShowKeyCheck.Location = New-Object System.Drawing.Point(335, 56)
$ShowKeyCheck.Size = New-Object System.Drawing.Size(60, 24)
$ShowKeyCheck.Add_CheckedChanged({
    $Script:ApiKeyText.UseSystemPasswordChar = -not $ShowKeyCheck.Checked
})
$Panel.Controls.Add($ShowKeyCheck)

$ModelLabel = New-Object System.Windows.Forms.Label
$ModelLabel.Text = "模型模式"
$ModelLabel.Location = New-Object System.Drawing.Point(18, 96)
$ModelLabel.Size = New-Object System.Drawing.Size(180, 22)
$Panel.Controls.Add($ModelLabel)

$Script:ModelCombo = New-Object System.Windows.Forms.ComboBox
$Script:ModelCombo.Location = New-Object System.Drawing.Point(18, 121)
$Script:ModelCombo.Size = New-Object System.Drawing.Size(380, 28)
$Script:ModelCombo.DropDownStyle = "DropDownList"
[void]$Script:ModelCombo.Items.Add("稳定编程模式 - deepseek-v4-pro[1m]")
[void]$Script:ModelCombo.Items.Add("快速省钱模式 - deepseek-v4-flash")
[void]$Script:ModelCombo.Items.Add("通用聊天模式 - deepseek-chat")
[void]$Script:ModelCombo.Items.Add("深度推理模式 - deepseek-reasoner")
[void]$Script:ModelCombo.Items.Add("自定义模型")
$Script:ModelCombo.SelectedIndex = 0
$Panel.Controls.Add($Script:ModelCombo)

$CustomClaudeLabel = New-Object System.Windows.Forms.Label
$CustomClaudeLabel.Text = "自定义 Claude 模型"
$CustomClaudeLabel.Location = New-Object System.Drawing.Point(18, 160)
$CustomClaudeLabel.Size = New-Object System.Drawing.Size(180, 22)
$Panel.Controls.Add($CustomClaudeLabel)

$Script:CustomClaudeText = New-Object System.Windows.Forms.TextBox
$Script:CustomClaudeText.Location = New-Object System.Drawing.Point(18, 183)
$Script:CustomClaudeText.Size = New-Object System.Drawing.Size(180, 26)
$Script:CustomClaudeText.Text = "deepseek-v4-pro[1m]"
$Panel.Controls.Add($Script:CustomClaudeText)

$CustomOpenAILabel = New-Object System.Windows.Forms.Label
$CustomOpenAILabel.Text = "自定义 OpenAI 模型"
$CustomOpenAILabel.Location = New-Object System.Drawing.Point(215, 160)
$CustomOpenAILabel.Size = New-Object System.Drawing.Size(180, 22)
$Panel.Controls.Add($CustomOpenAILabel)

$Script:CustomOpenAIText = New-Object System.Windows.Forms.TextBox
$Script:CustomOpenAIText.Location = New-Object System.Drawing.Point(215, 183)
$Script:CustomOpenAIText.Size = New-Object System.Drawing.Size(180, 26)
$Script:CustomOpenAIText.Text = "deepseek-chat"
$Panel.Controls.Add($Script:CustomOpenAIText)

$ToolsLabel = New-Object System.Windows.Forms.Label
$ToolsLabel.Text = "选择要配置的 Agent 工具"
$ToolsLabel.Location = New-Object System.Drawing.Point(18, 222)
$ToolsLabel.Size = New-Object System.Drawing.Size(250, 22)
$Panel.Controls.Add($ToolsLabel)

$Script:ToolsCheckedList = New-Object System.Windows.Forms.CheckedListBox
$Script:ToolsCheckedList.Location = New-Object System.Drawing.Point(18, 247)
$Script:ToolsCheckedList.Size = New-Object System.Drawing.Size(380, 92)
$Script:ToolsCheckedList.CheckOnClick = $true
$tools = @(
    "Claude Code",
    "Cline",
    "Roo Code",
    "Kilo Code",
    "Continue",
    "OpenCode",
    "Hermes Agent",
    "OpenAI-Compatible 通用配置"
)
foreach ($tool in $tools) {
    [void]$Script:ToolsCheckedList.Items.Add($tool)
}
for ($i = 0; $i -lt $Script:ToolsCheckedList.Items.Count; $i++) {
    $Script:ToolsCheckedList.SetItemChecked($i, $true)
}
$Panel.Controls.Add($Script:ToolsCheckedList)

$Script:CurrentSessionCheck = New-Object System.Windows.Forms.CheckBox
$Script:CurrentSessionCheck.Text = "仅当前会话生效，不写入永久用户环境变量"
$Script:CurrentSessionCheck.Location = New-Object System.Drawing.Point(18, 355)
$Script:CurrentSessionCheck.Size = New-Object System.Drawing.Size(380, 24)
$Panel.Controls.Add($Script:CurrentSessionCheck)

# 中间操作区
$ActionPanel = New-Object System.Windows.Forms.GroupBox
$ActionPanel.Text = "操作区"
$ActionPanel.Location = New-Object System.Drawing.Point(460, 82)
$ActionPanel.Size = New-Object System.Drawing.Size(370, 405)
$ActionPanel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($ActionPanel)

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 155,
        [int]$H = 38
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $btn.FlatStyle = "Flat"
    $btn.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    return $btn
}

$BtnConfigure = New-Button "一键配置 Agent" 20 30 155 42
$BtnConfigure.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
$BtnConfigure.Add_Click({ Configure-All })
$ActionPanel.Controls.Add($BtnConfigure)

$BtnInstallClaude = New-Button "安装 Claude Code" 195 30 155 42
$BtnInstallClaude.Add_Click({ Install-ClaudeCode })
$ActionPanel.Controls.Add($BtnInstallClaude)

$BtnTestApi = New-Button "测试连接" 20 85
$BtnTestApi.Add_Click({ [void](Test-DeepSeekApi) })
$ActionPanel.Controls.Add($BtnTestApi)

$BtnRepair = New-Button "修复 Auth conflict" 195 85
$BtnRepair.Add_Click({
    try {
        $target = Get-EnvTarget
        Backup-CurrentConfig -Target $target
        Repair-AuthConflict -Target $target
        $profile = Get-ModelProfile
        $tools = Get-SelectedTools
        Generate-DiagnosticReport -Target $target -Profile $profile -Tools $tools
        Update-HealthScore
        Show-InfoBox "Auth conflict 修复完成。"
    } catch {
        Show-ErrorBox "修复失败：$($_.Exception.Message)"
    }
})
$ActionPanel.Controls.Add($BtnRepair)

$BtnDetect = New-Button "检测环境" 20 140
$BtnDetect.Add_Click({ Detect-Environment })
$ActionPanel.Controls.Add($BtnDetect)

$BtnExport = New-Button "导出日志" 195 140
$BtnExport.Add_Click({ Export-LogAndOpenFolder })
$ActionPanel.Controls.Add($BtnExport)

$BtnRestore = New-Button "恢复备份" 20 195
$BtnRestore.BackColor = [System.Drawing.Color]::FromArgb(254, 249, 195)
$BtnRestore.Add_Click({ Restore-Backup })
$ActionPanel.Controls.Add($BtnRestore)

$BtnHelpPack = New-Button "导出求助包 zip" 195 195
$BtnHelpPack.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
$BtnHelpPack.Add_Click({ Export-HelpPackZip })
$ActionPanel.Controls.Add($BtnHelpPack)

$BtnOpenFolder = New-Button "打开工具目录" 20 250
$BtnOpenFolder.Add_Click({ Start-Process explorer.exe $Script:ToolkitRoot })
$ActionPanel.Controls.Add($BtnOpenFolder)

$BtnUninstall = New-Button "卸载配置" 195 250
$BtnUninstall.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
$BtnUninstall.Add_Click({ Uninstall-Config })
$ActionPanel.Controls.Add($BtnUninstall)

$GuideBox = New-Object System.Windows.Forms.TextBox
$GuideBox.Location = New-Object System.Drawing.Point(20, 310)
$GuideBox.Size = New-Object System.Drawing.Size(330, 70)
$GuideBox.Multiline = $true
$GuideBox.ReadOnly = $true
$GuideBox.ScrollBars = "Vertical"
$GuideBox.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$GuideBox.Text = "流程：输入 API Key → 选择工具 → 一键配置 → 测试连接 → 选择项目目录 → 生成 CLAUDE.md → 启动 Claude Code。"
$ActionPanel.Controls.Add($GuideBox)

# 右侧健康评分
$HealthPanel = New-Object System.Windows.Forms.GroupBox
$HealthPanel.Text = "V4 Pro 环境健康评分"
$HealthPanel.Location = New-Object System.Drawing.Point(850, 82)
$HealthPanel.Size = New-Object System.Drawing.Size(290, 405)
$HealthPanel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($HealthPanel)

$Script:HealthScoreLabel = New-Object System.Windows.Forms.Label
$Script:HealthScoreLabel.Text = "环境健康评分：0 / 100"
$Script:HealthScoreLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 12, [System.Drawing.FontStyle]::Bold)
$Script:HealthScoreLabel.Location = New-Object System.Drawing.Point(18, 32)
$Script:HealthScoreLabel.Size = New-Object System.Drawing.Size(250, 26)
$HealthPanel.Controls.Add($Script:HealthScoreLabel)

$Script:HealthBar = New-Object System.Windows.Forms.ProgressBar
$Script:HealthBar.Location = New-Object System.Drawing.Point(18, 68)
$Script:HealthBar.Size = New-Object System.Drawing.Size(250, 24)
$Script:HealthBar.Minimum = 0
$Script:HealthBar.Maximum = 100
$HealthPanel.Controls.Add($Script:HealthBar)

$Script:HealthStatusLabel = New-Object System.Windows.Forms.Label
$Script:HealthStatusLabel.Text = "状态：等待检测"
$Script:HealthStatusLabel.Location = New-Object System.Drawing.Point(18, 104)
$Script:HealthStatusLabel.Size = New-Object System.Drawing.Size(250, 24)
$HealthPanel.Controls.Add($Script:HealthStatusLabel)

$Script:HealthDetailBox = New-Object System.Windows.Forms.TextBox
$Script:HealthDetailBox.Location = New-Object System.Drawing.Point(18, 138)
$Script:HealthDetailBox.Size = New-Object System.Drawing.Size(250, 240)
$Script:HealthDetailBox.Multiline = $true
$Script:HealthDetailBox.ReadOnly = $true
$Script:HealthDetailBox.ScrollBars = "Vertical"
$Script:HealthDetailBox.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$HealthPanel.Controls.Add($Script:HealthDetailBox)

# 项目区
$ProjectPanel = New-Object System.Windows.Forms.GroupBox
$ProjectPanel.Text = "V4 Pro Claude Code 项目启动器"
$ProjectPanel.Location = New-Object System.Drawing.Point(20, 500)
$ProjectPanel.Size = New-Object System.Drawing.Size(1120, 125)
$ProjectPanel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($ProjectPanel)

$ProjectPathLabel = New-Object System.Windows.Forms.Label
$ProjectPathLabel.Text = "项目目录"
$ProjectPathLabel.Location = New-Object System.Drawing.Point(18, 30)
$ProjectPathLabel.Size = New-Object System.Drawing.Size(80, 24)
$ProjectPanel.Controls.Add($ProjectPathLabel)

$Script:ProjectPathText = New-Object System.Windows.Forms.TextBox
$Script:ProjectPathText.Location = New-Object System.Drawing.Point(90, 28)
$Script:ProjectPathText.Size = New-Object System.Drawing.Size(540, 26)
$ProjectPanel.Controls.Add($Script:ProjectPathText)

$BtnSelectProject = New-Button "选择目录" 645 26 95 30
$BtnSelectProject.Add_Click({ Select-ProjectFolder })
$ProjectPanel.Controls.Add($BtnSelectProject)

$BtnGenerateClaude = New-Button "生成 CLAUDE.md" 755 26 135 30
$BtnGenerateClaude.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
$BtnGenerateClaude.Add_Click({ Generate-ClaudeMd })
$ProjectPanel.Controls.Add($BtnGenerateClaude)

$BtnLaunchClaude = New-Button "启动 Claude Code" 905 26 150 30
$BtnLaunchClaude.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
$BtnLaunchClaude.Add_Click({ Launch-ClaudeCodeInProject })
$ProjectPanel.Controls.Add($BtnLaunchClaude)

$ProjectGoalLabel = New-Object System.Windows.Forms.Label
$ProjectGoalLabel.Text = "项目目标"
$ProjectGoalLabel.Location = New-Object System.Drawing.Point(18, 70)
$ProjectGoalLabel.Size = New-Object System.Drawing.Size(80, 24)
$ProjectPanel.Controls.Add($ProjectGoalLabel)

$Script:ProjectGoalText = New-Object System.Windows.Forms.TextBox
$Script:ProjectGoalText.Location = New-Object System.Drawing.Point(90, 68)
$Script:ProjectGoalText.Size = New-Object System.Drawing.Size(430, 26)
$Script:ProjectGoalText.Text = "帮助我完成项目开发、调试、测试、文档和打包。"
$ProjectPanel.Controls.Add($Script:ProjectGoalText)

$TechStackLabel = New-Object System.Windows.Forms.Label
$TechStackLabel.Text = "技术栈"
$TechStackLabel.Location = New-Object System.Drawing.Point(540, 70)
$TechStackLabel.Size = New-Object System.Drawing.Size(70, 24)
$ProjectPanel.Controls.Add($TechStackLabel)

$Script:TechStackText = New-Object System.Windows.Forms.TextBox
$Script:TechStackText.Location = New-Object System.Drawing.Point(600, 68)
$Script:TechStackText.Size = New-Object System.Drawing.Size(455, 26)
$Script:TechStackText.Text = "Next.js / React / TypeScript / Tailwind CSS v4 / Node.js，或由 Claude 自动识别。"
$ProjectPanel.Controls.Add($Script:TechStackText)


# V4 Pro 工具箱
$V4Panel = New-Object System.Windows.Forms.GroupBox
$V4Panel.Text = "V4 Pro 工具箱：Provider / 加密 Key / 模型测速 / 依赖安装 / EXE 打包"
$V4Panel.Location = New-Object System.Drawing.Point(20, 635)
$V4Panel.Size = New-Object System.Drawing.Size(1120, 100)
$V4Panel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($V4Panel)

$ProviderLabel = New-Object System.Windows.Forms.Label
$ProviderLabel.Text = "Provider"
$ProviderLabel.Location = New-Object System.Drawing.Point(18, 28)
$ProviderLabel.Size = New-Object System.Drawing.Size(70, 24)
$V4Panel.Controls.Add($ProviderLabel)

$Script:ProviderCombo = New-Object System.Windows.Forms.ComboBox
$Script:ProviderCombo.Location = New-Object System.Drawing.Point(90, 25)
$Script:ProviderCombo.Size = New-Object System.Drawing.Size(190, 28)
$Script:ProviderCombo.DropDownStyle = "DropDownList"
[void]$Script:ProviderCombo.Items.Add("DeepSeek 官方")
[void]$Script:ProviderCombo.Items.Add("OpenRouter")
[void]$Script:ProviderCombo.Items.Add("OpenAI 官方")
[void]$Script:ProviderCombo.Items.Add("Anthropic 官方")
[void]$Script:ProviderCombo.Items.Add("SiliconFlow 硅基流动")
[void]$Script:ProviderCombo.Items.Add("Ollama 本地")
[void]$Script:ProviderCombo.Items.Add("LM Studio 本地")
$Script:ProviderCombo.SelectedIndex = 0
$Script:ProviderCombo.Add_SelectedIndexChanged({ Apply-V4ProviderDefaults })
$V4Panel.Controls.Add($Script:ProviderCombo)

$BaseUrlLabel = New-Object System.Windows.Forms.Label
$BaseUrlLabel.Text = "Base URL"
$BaseUrlLabel.Location = New-Object System.Drawing.Point(300, 28)
$BaseUrlLabel.Size = New-Object System.Drawing.Size(70, 24)
$V4Panel.Controls.Add($BaseUrlLabel)

$Script:ProviderBaseUrlText = New-Object System.Windows.Forms.TextBox
$Script:ProviderBaseUrlText.Location = New-Object System.Drawing.Point(370, 25)
$Script:ProviderBaseUrlText.Size = New-Object System.Drawing.Size(280, 26)
$Script:ProviderBaseUrlText.Text = "https://api.deepseek.com"
$V4Panel.Controls.Add($Script:ProviderBaseUrlText)

$BtnSaveKey = New-Button "加密保存 Key" 665 22 110 32
$BtnSaveKey.BackColor = [System.Drawing.Color]::FromArgb(219, 234, 254)
$BtnSaveKey.Add_Click({ Save-V4EncryptedApiKey })
$V4Panel.Controls.Add($BtnSaveKey)

$BtnLoadKey = New-Button "读取 Key" 785 22 85 32
$BtnLoadKey.Add_Click({ Load-V4EncryptedApiKey })
$V4Panel.Controls.Add($BtnLoadKey)

$BtnSpeed = New-Button "模型测速" 880 22 90 32
$BtnSpeed.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
$BtnSpeed.Add_Click({ Test-V4ModelSpeed })
$V4Panel.Controls.Add($BtnSpeed)

$BtnWinget = New-Button "安装 Node/Git" 980 22 120 32
$BtnWinget.Add_Click({ Install-V4NodeGitWithWinget })
$V4Panel.Controls.Add($BtnWinget)

$V4Tip = New-Object System.Windows.Forms.Label
$V4Tip.Text = "提示：Provider 会自动填充 Base URL 和默认模型；模型测速使用 OpenAI-Compatible /chat/completions；API Key 加密保存使用 Windows DPAPI。"
$V4Tip.Location = New-Object System.Drawing.Point(18, 64)
$V4Tip.Size = New-Object System.Drawing.Size(810, 24)
$V4Tip.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$V4Panel.Controls.Add($V4Tip)

$BtnRelease = New-Button "生成发布/EXE打包文件" 850 60 250 30
$BtnRelease.BackColor = [System.Drawing.Color]::FromArgb(254, 249, 195)
$BtnRelease.Add_Click({ Generate-V4ReleaseFiles })
$V4Panel.Controls.Add($BtnRelease)


# 日志面板
$LogPanel = New-Object System.Windows.Forms.GroupBox
$LogPanel.Text = "实时日志"
$LogPanel.Location = New-Object System.Drawing.Point(20, 750)
$LogPanel.Size = New-Object System.Drawing.Size(1120, 95)
$LogPanel.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($LogPanel)

$Script:LogBox = New-Object System.Windows.Forms.TextBox
$Script:LogBox.Location = New-Object System.Drawing.Point(15, 24)
$Script:LogBox.Size = New-Object System.Drawing.Size(1090, 58)
$Script:LogBox.Multiline = $true
$Script:LogBox.ScrollBars = "Vertical"
$Script:LogBox.ReadOnly = $true
$Script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$Script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$Script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$LogPanel.Controls.Add($Script:LogBox)

# 初始化
$Script:LastApiTestOk = $null
Add-Log "DeepSeek Agent Toolkit V4 Pro GUI 已启动。" "OK"
Add-Log "工具目录：$Script:ToolkitRoot" "INFO"
Add-Log "V4 Pro 新功能：Provider 管理、API Key 加密保存、模型测速、winget 依赖安装、EXE 打包，同时保留 V3.1 全部功能。" "INFO"

$Form.Add_Shown({
    $Form.Activate()
    Update-HealthScore
})

[void][System.Windows.Forms.Application]::Run($Form)
