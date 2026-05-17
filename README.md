DeepSeek Agent Toolkit V4 Pro GUI
一、版本定位
V4 Pro 是在 V3.1 GUI 基础上的产品化增强版。

它保留 V3.1 全部功能，并新增：

1. Provider 管理
2. API Key 加密保存 / 读取
3. OpenAI-Compatible 模型测速
4. winget 一键安装 Node.js LTS / Git
5. EXE 打包发布文件生成
6. 继续保留环境健康评分
7. 继续保留一键恢复备份
8. 继续保留一键导出求助包 zip
9. 继续保留一键生成 CLAUDE.md
10. 继续保留一键选择项目目录并启动 Claude Code
二、启动方式
powershell -ExecutionPolicy Bypass -File .\deepseek-agent-toolkit-v4-pro.ps1
三、V4 Pro 新增功能说明
1. Provider 管理
支持在 GUI 中选择：

DeepSeek 官方
OpenRouter
OpenAI 官方
Anthropic 官方
SiliconFlow 硅基流动
Ollama 本地
LM Studio 本地
选择 Provider 后，会自动填充：

Base URL
默认模型
推理模型
2. API Key 加密保存
点击：

加密保存 Key
会把 API Key 使用 Windows DPAPI 加密保存到：

桌面\DeepSeek-Agent-Toolkit-V4-Pro-GUI\config\v4-provider-key.encrypted.json
这个加密文件通常只能由当前 Windows 用户在当前电脑解密。

点击：

读取 Key
可以把加密保存的 Key 读回输入框。

3. 模型测速
点击：

模型测速
会调用当前 Provider 的 OpenAI-Compatible 接口：

{Base URL}/chat/completions
并输出：

Provider
Model
耗时 ms
返回内容
测速报告会保存到：

reports/model-speed-时间.txt
4. winget 安装 Node.js / Git
点击：

安装 Node/Git
会打开新的 PowerShell 窗口执行：

winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
winget install Git.Git -e --accept-source-agreements --accept-package-agreements
安装完成后建议重新打开 V4 Pro。

5. 生成发布 / EXE 打包文件
点击：

生成发布/EXE打包文件
会生成：

release/
├─ deepseek-agent-toolkit-v4-pro.ps1
├─ build-v4-exe.ps1
└─ README-V4-Pro.md
进入 release 目录后运行：

powershell -ExecutionPolicy Bypass -File .\build-v4-exe.ps1
即可尝试打包为：

DeepSeek-Agent-Toolkit-V4-Pro.exe
打包依赖 PowerShell 模块：

ps2exe
脚本会自动尝试安装。

四、推荐使用流程
1. 打开 V4 Pro GUI
2. 点击“检测环境”，查看健康评分
3. 选择 Provider，例如 DeepSeek 官方
4. 输入 API Key
5. 点击“加密保存 Key”
6. 选择模型模式和 Agent 工具
7. 点击“一键配置 Agent”
8. 点击“测试连接”
9. 点击“模型测速”
10. 选择项目目录
11. 点击“生成 CLAUDE.md”
12. 点击“启动 Claude Code”
五、运行后生成目录
默认生成到桌面：

DeepSeek-Agent-Toolkit-V4-Pro-GUI/
├─ config/
├─ backups/
├─ logs/
├─ reports/
├─ help-packs/
└─ release/
六、注意事项
API Key 安全
V4 Pro 的日志、诊断报告、求助包会尽量脱敏 API Key。
但你仍然应该在发送求助包前自行检查。

本地模型
Ollama / LM Studio 的测速依赖本地服务是否已启动。

常见地址：

Ollama: http://localhost:11434/v1
LM Studio: http://localhost:1234/v1
Anthropic 官方
Anthropic 官方不是 OpenAI-Compatible 接口，因此 V4 Pro 的“模型测速”按钮不适用于 Anthropic 官方 Provider。

Claude Code + DeepSeek
DeepSeek Claude Code 推荐：

ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_AUTH_TOKEN=你的 DeepSeek API Key
不要同时保留：

ANTHROPIC_API_KEY
ANTHROPIC_AUTH_TOKEN
否则可能出现 Auth conflict。
