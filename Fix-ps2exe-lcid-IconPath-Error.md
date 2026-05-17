# 修复 Invoke-ps2exe lcid 参数转换失败

## 你遇到的错误

```text
Invoke-ps2exe : 无法处理对参数“lcid”的参数转换。
无法将值“”转换为类型“System.Int32”。
错误:“索引超出了数组界限。”
所在位置 ...build-v4-pro-installer.ps1:52 字符: 25
+     -iconFile $IconPath `r
```

## 原因

你的打包脚本里这一行被错误写成了类似：

```powershell
-iconFile $IconPath `r
```

PowerShell 的换行续行符应该是单独的反引号：

```powershell
-iconFile $IconPath `
```

而不是：

```powershell
-iconFile $IconPath `r
```

这个 `r` 会破坏参数解析，导致 ps2exe 把后面的内容错当成 `lcid` 参数。

## 最简单修复

使用修复版脚本：

```text
build-v4-pro-installer-fixed.ps1
```

把它放到你的项目目录，和这些文件同级：

```text
deepseek-agent-toolkit-v4-pro.ps1
deepseek-agent-toolkit-v4-pro.ico
DeepSeek-Agent-Toolkit-V4-Pro.iss
build-v4-pro-installer-fixed.ps1
```

然后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-v4-pro-installer-fixed.ps1
```

## 手动修复方式

打开原来的：

```text
build-v4-pro-installer.ps1
```

找到：

```powershell
-iconFile $IconPath `r
```

改成：

```powershell
-iconFile $IconPath `
```

注意：

1. 反引号 ` 必须是该行最后一个字符。
2. 反引号后面不能有空格。
3. 不能写成 `r。
4. 下一行继续写参数，例如：

```powershell
-iconFile $IconPath `
-noConsole `
-STA
```

## 推荐做法

直接用我给你的修复版脚本，不要继续用被自动补丁改坏的旧脚本。
