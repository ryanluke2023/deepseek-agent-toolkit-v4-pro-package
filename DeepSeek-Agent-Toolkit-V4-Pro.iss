; DeepSeek Agent Toolkit V4 Pro Inno Setup 安装包配置
; 使用：
; 1. 先运行 build-v4-pro-installer.ps1
; 2. 或者在 Inno Setup Compiler 中打开本文件编译

#define MyAppName "DeepSeek Agent Toolkit V4 Pro"
#define MyAppVersion "4.0.0"
#define MyAppPublisher "DeepSeek Agent Toolkit"
#define MyAppExeName "DeepSeek-Agent-Toolkit-V4-Pro.exe"

[Setup]
AppId={{AFA3F6D2-4A3C-4B4B-9E86-DFE1B4E5A7A4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\DeepSeek Agent Toolkit V4 Pro
DefaultGroupName=DeepSeek Agent Toolkit V4 Pro
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=DeepSeek-Agent-Toolkit-V4-Pro-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupIconFile=deepseek-agent-toolkit-v4-pro.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]

Source: "deepseek-agent-toolkit-v4-pro.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "DeepSeek-Agent-Toolkit-V4-Pro-README.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "DeepSeek-Agent-Toolkit-V4-Pro-RELEASE-NOTES.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
