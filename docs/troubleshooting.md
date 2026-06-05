# Hermit 排障手册

本文档记录 Hermit 安装和运行阶段的常见问题、定位方法和预期处理方式。

## 日志位置

安装脚本将日志写入：

```text
%LOCALAPPDATA%\Hermit\logs\
```

日志文件命名：

```text
install-YYYYMMDD-HHMMSS.log
```

安装日志包含主安装步骤、资源校验输出、退出码和未捕获异常摘要。需要给维护者提交排障信息时，先运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\collect-logs.ps1
```

该命令会把本机日志打包到项目内 `diagnostics/` 目录。诊断包不应提交到公开仓库。

## 常见问题

### 安装脚本退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功，或 dry-run 安装计划验证通过 |
| `1` | 校验、环境、安装器、配置或自检失败 |
| `2` | 公开 bootstrap 清单未就绪，脚本未执行安装动作 |

### 先验证安装计划

真实安装前先运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -DryRun
```

该模式不会执行安装器、不会写入配置、不会复制 Skill，也不会创建 `C:\HermitWorkspace`。

### 资源文件缺失

现象：

- 安装脚本在资源校验阶段中止。
- 输出缺失的文件路径。

处理：

- 按 `docs/installation.md` 准备本地安装资源。
- 打包机器上更新 `assets/manifest.local.json` 和 `assets/checksums.local.sha256`。
- 公开仓库只更新 bootstrap 用的 `assets/manifest.json` 和 `assets/checksums.sha256`。

### SHA256 校验失败

现象：

- 校验脚本提示文件哈希不匹配。

处理：

- 删除异常文件。
- 从官方渠道重新下载。
- 重新计算 SHA256 并更新清单。

### 未捕获安装异常

现象：

- 日志中出现 `Unhandled installer error`。
- 控制台只显示退出码 `1`。

处理：

- 打开同一份 `install-YYYYMMDD-HHMMSS.log` 查看异常摘要和脚本栈。
- 运行 `scripts\collect-logs.ps1` 生成诊断包。
- 检查最近一次修改的清单路径、zip 包、安装器参数和权限环境。

### PowerShell 执行策略阻止脚本

现象：

- 直接运行 `.ps1` 失败。

处理：

- 使用 `一键唤醒隐士.bat` 启动。
- bat 应使用 `-ExecutionPolicy Bypass` 仅对当前进程绕过策略。

### Python 版本过低

现象：

- 系统已有 Python，但版本小于 3.10。

处理：

- 安装脚本会使用项目内 Python 3.11.9 安装包。
- 如果选择系统级安装，脚本必须避免重复追加 PATH。

### 运行期配置未完成

现象：

- 日志中出现 `Runtime config not configured`。
- 安装仍然完成，但后续外部 API 或移动端远程控制不可用。

处理：

- 提前复制 `assets/config/runtime.example.json` 为 `assets/config/runtime.local.json`，填入真实值后重新安装。
- 或安装后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1
```

配置文件会写入 `%LOCALAPPDATA%\Hermit\config\runtime.secrets.json`。日志不应包含 API Key、Token 或 Webhook secret。

### Hermes 配置被覆盖

现象：

- Hermes 旧配置丢失或行为异常。

处理：

- 从 `%LOCALAPPDATA%\Hermit\backup\` 找到安装前备份。
- 关闭 Hermes 后还原配置。

### Word 文件被占用

现象：

- Word Skill 返回文件被占用或无法保存。

处理：

- 关闭 Word 中打开的目标文档。
- 重新运行 Skill。
- 原文件不得被修改。

## 敏感信息处理

- 日志不得打印 API Key、Token、Cookie。
- 配置备份目录只应授予当前用户读写权限。
- 真实配置不应提交到仓库。
