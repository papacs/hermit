# Hermit 安装与本地资源准备

本文档描述 Hermit 的目标安装方式和本地安装资源准备流程。当前脚本已实现 dry-run 和安装流程编排；真实安装仍需在目标 Windows 环境完成验收。Hermit 的运行期默认联网，本地资源主要用于让安装更快、更稳定，并减少目标机器安装时的下载依赖。

## 目标安装流程

1. 用户双击 `一键唤醒隐士.bat`。
2. bat 入口检查管理员权限，并在需要时触发 UAC 提权。
3. bat 使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass` 调用 `scripts/install.ps1`。
4. `install.ps1` 初始化日志目录。
5. `install.ps1` 调用 `scripts/verify-assets.ps1` 校验本地安装资源。
6. 脚本检测 Windows、PowerShell、CPU 架构和 Python 版本。
7. 脚本安装或复用 Python，并从 `assets/wheels/` 本地安装 Python 依赖。
8. 脚本静默安装 Hermes 桌面端。
9. 脚本备份现有 Hermes 配置，并注入 `assets/config/config_template.zip`。
10. 脚本复制 `hermit_skills/` 到 `%USERPROFILE%\Hermit_Skills\`。
11. 脚本运行自检并输出结果。

## 本地安装资源目录

```text
assets/
├── installers/
│   ├── python-3.11.9-amd64.exe
│   └── hermes-desktop-setup.exe
├── wheels/
├── config/
│   ├── config_template.zip
│   └── config.example.json
├── manifest.json
└── checksums.sha256
```

## Python 安装包

将 Python 3.11.9 Windows x64 安装包放入：

```text
assets/installers/python-3.11.9-amd64.exe
```

安装脚本会优先复用已存在且版本满足要求的 Python。只有找不到 Python >= 3.10 时，才使用本地安装包。

## Python wheel 包

在可联网的打包机器上执行：

```powershell
py -3.11 -m pip download `
  --dest assets/wheels `
  --only-binary=:all: `
  python-docx
```

目标机器安装依赖时必须优先使用本地 wheel：

```powershell
python -m pip install --no-index --find-links assets/wheels python-docx
```

## Hermes 安装包

将 Hermes 桌面端安装包放入：

```text
assets/installers/hermes-desktop-setup.exe
```

静默安装参数需要基于实际安装包验证。脚本不得假设所有安装器都支持相同参数。

## 配置模板

配置模板放入：

```text
assets/config/config_template.zip
```

配置模板默认不应包含真实 API Key 或 Token。确需分发私有配置时，应使用受控分发包，并保证日志不输出敏感值。

## 校验文件

`assets/checksums.sha256` 使用如下格式：

```text
<sha256>  assets/installers/python-3.11.9-amd64.exe
<sha256>  assets/installers/hermes-desktop-setup.exe
```

校验脚本必须跳过空行和以 `#` 开头的注释行。

## 本地清单策略

为了兼顾本地资源加速安装和开源发布，Hermit 使用两套清单：

- `assets/manifest.json` 和 `assets/checksums.sha256`：公开仓库中的 bootstrap 清单，默认 `packageReady=false`。
- `assets/manifest.local.json` 和 `assets/checksums.local.sha256`：打包机器上的本地清单，记录真实安装包、wheel 包和配置模板哈希，默认被 `.gitignore` 排除。

`scripts/install.ps1` 会优先使用本地清单；如果本地清单不存在，则回退到公开 bootstrap 清单。

本地资源校验命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify-assets.ps1 -ChecksumFile assets\checksums.local.sha256
```

如果需要把资源校验输出并入安装日志，可传入 `-LogFile`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\verify-assets.ps1 -ChecksumFile assets\checksums.local.sha256 -LogFile "$env:LOCALAPPDATA\Hermit\logs\manual-verify.log"
```

当前已确认的官方下载来源：

- Python 3.11.9 Windows x64：`https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe`
- Hermes Desktop Windows：`https://hermes-assets.nousresearch.com/Hermes-Setup.exe`

## Dry-run 验证

完整安装脚本支持 dry-run。该模式会执行资源校验、环境检查和安装计划生成，但不会运行安装器、不会写入 Hermes 配置、不会复制 Skill，也不会创建沙箱目录。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -DryRun
```

退出码：

- `0`：安装计划验证通过。
- `1`：校验或环境错误。
- `2`：公开 bootstrap 清单未就绪。

## 日志与诊断

安装脚本会将日志写入 `%LOCALAPPDATA%\Hermit\logs\install-YYYYMMDD-HHMMSS.log`。日志包含主安装步骤、资源校验输出、dry-run 计划、失败退出码和未捕获异常摘要。

收集日志诊断包：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\collect-logs.ps1
```

## Hermes 配置路径

Hermes Desktop 官方文档说明 Windows 运行时数据位于 `%LOCALAPPDATA%\hermes`。Hermit 以该目录为配置注入目标，并在写入前备份到 `%LOCALAPPDATA%\Hermit\backup\`。如果检测到旧 `%APPDATA%\Hermes` 目录，也会做兼容备份，但不会把它作为主要写入目标。
