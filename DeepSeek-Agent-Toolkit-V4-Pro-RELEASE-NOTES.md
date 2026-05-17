# DeepSeek Agent Toolkit V4 Pro 更新说明

## 从 V3.1 升级到 V4 Pro

新增：

1. Provider 管理
   - DeepSeek 官方
   - OpenRouter
   - OpenAI 官方
   - Anthropic 官方
   - SiliconFlow 硅基流动
   - Ollama 本地
   - LM Studio 本地

2. API Key 加密保存
   - 使用 Windows DPAPI
   - 当前用户/当前电脑可解密
   - 避免明文长期显示在输入框之外

3. 模型测速
   - 测试 /chat/completions
   - 输出耗时 ms
   - 保存测速报告

4. winget 依赖安装
   - Node.js LTS
   - Git for Windows

5. EXE 打包支持
   - 生成 build-v4-exe.ps1
   - 使用 ps2exe 打包

保留：

- 环境健康评分
- 恢复备份
- 求助包 zip
- CLAUDE.md 生成
- 项目目录启动 Claude Code
- DeepSeek / Claude Code / OpenAI-Compatible 配置
