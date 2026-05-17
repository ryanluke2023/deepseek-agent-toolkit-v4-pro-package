# DeepSeek Agent Toolkit V4 Pro 打包成 EXE 安装包教程

## 一、你需要的文件

把下面文件放在同一个文件夹：

```text
deepseek-agent-toolkit-v4-pro.ps1
build-v4-pro-installer.ps1
DeepSeek-Agent-Toolkit-V4-Pro.iss
DeepSeek-Agent-Toolkit-V4-Pro-README.md
DeepSeek-Agent-Toolkit-V4-Pro-RELEASE-NOTES.md
```

其中最重要的是：

```text
deepseek-agent-toolkit-v4-pro.ps1
build-v4-pro-installer.ps1
DeepSeek-Agent-Toolkit-V4-Pro.iss
```

## 二、先安装 Inno Setup

### 方法 1：官网下载

搜索并安装：

```text
Inno Setup 6
```

### 方法 2：winget 安装

```powershell
winget install JRSoftware.InnoSetup -e
```

## 三、执行打包命令

在文件所在目录打开 PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build-v4-pro-installer.ps1
```

## 四、打包成功后会得到什么？

### 1. 便携 EXE

```text
build\DeepSeek-Agent-Toolkit-V4-Pro.exe
```

这个可以直接双击运行。

### 2. 正式安装包

```text
dist\DeepSeek-Agent-Toolkit-V4-Pro-Setup.exe
```

这个就是可以发给新人的安装包。

## 五、安装包效果

安装包会：

```text
1. 安装 DeepSeek Agent Toolkit V4 Pro
2. 创建开始菜单快捷方式
3. 可选创建桌面快捷方式
4. 安装完成后可自动启动软件
5. 支持 Windows 卸载
```

## 六、常见问题

### 1. Install-Module ps2exe 报错

先执行：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

然后重新运行打包脚本。

### 2. 找不到 ISCC.exe

说明没有安装 Inno Setup。安装后重新打开 PowerShell。

### 3. EXE 打开没反应

请确认打包时用了：

```powershell
-noConsole
-STA
```

本教程里的脚本已经加上。

### 4. 中文乱码

本套文件使用 UTF-8 with BOM 保存，适合 Windows PowerShell 5.1。
