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

`collect-logs.ps1` 会同时收集 `%LOCALAPPDATA%\Hermit\logs\` 和 `%LOCALAPPDATA%\hermes\logs\`。如果 Hermes 的 `bootstrap-installer.log` 是 0KB，说明外部 Hermes 安装器没有写出有效诊断内容；Hermit 主日志仍以 `install-YYYYMMDD-HHMMSS.log` 为准。

## 常见问题

### 安装脚本退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功，或 dry-run 安装计划验证通过 |
| `1` | 校验、环境、安装器、配置或自检失败 |
| `2` | 当前 manifest 未就绪，且联网准备被禁用或未执行 |

如果从 GitHub 直接克隆仓库后运行安装，公开仓库已包含固定版本的 Python/Hermes 安装器、CPython 3.11 wheels 和无密钥配置模板。正常情况下不会再联网下载 wheel；只有当前 manifest 被改成未就绪，或资源被删除/校验失败时，才需要运行 `scripts/prepare-assets.ps1` 重新准备资源。

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

### Python 版本不匹配

现象：

- 系统已有 Python，但不是 3.11。
- 日志中出现 `Could not find a version that satisfies the requirement lxml`。

处理：

- 当前本地 wheel 面向 CPython 3.11 / Windows x64，安装脚本会强制使用 Python 3.11 创建 venv。
- 如果系统没有 Python 3.11，安装脚本会使用项目内 Python 3.11.9 安装包创建 Hermit 管理的 Python。
- 不应使用 Python 3.10 创建 Hermit venv，否则 `lxml` 的 `cp311` wheel 不兼容。

### Python 依赖安装失败

现象：

- 日志中出现 `Local pip install failed`。
- 或 pip 输出显示已安装到用户全局 `site-packages`。

处理：

- 新版本安装脚本会使用 `%LOCALAPPDATA%\Hermit\runtime\venv`，不会再向系统 Python 或用户全局 `site-packages` 写包。
- 先运行 dry-run 确认日志中出现 `Python virtual environment` 和 `Would install Python packages into virtual environment`。
- 确认 `assets/wheels/` 中存在 `python-docx`、`lxml` 和 `typing_extensions` 对应 wheel。

### 只拉代码后资源缺失

现象：

- 日志显示 `Local package is not ready`。
- 或安装器返回退出码 `2`。

处理：

- 保持联网，直接运行 `一键唤醒隐士.bat`，安装器会尝试自动准备本地资源。
- 或手动运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\prepare-assets.ps1
```

- 如果机器不能联网，直接使用仓库已提交的公开离线资源；如需使用自定义资源包，再从已准备好的机器复制 `assets/manifest.local.json`、`assets/checksums.local.sha256`、`assets/installers/`、`assets/wheels/` 和 `assets/config/config_template.zip`。

### Hermes Setup 弹窗并提示 uv installation failed

现象：

- 安装过程中弹出 `Hermes Setup` 图形界面。
- 界面显示 `INSTALL DIDN'T FINISH` 和 `uv installation failed`。
- `%LOCALAPPDATA%\hermes\logs\bootstrap-installer.log` 存在但大小为 0KB。

原因：

- 这是 Hermes Desktop 外部安装器内部 bootstrap 失败，不是 Hermit 的 Python venv、wheel、Word Skill 或配置安装失败。
- 该安装器当前不是可靠静默安装器，且失败时可能不写有效日志。
- 该安装器会从 GitHub 下载 Hermes 自己的 `install.ps1`，再安装 `uv`、Git、Node.js、ripgrep、ffmpeg，并 clone/build Hermes 桌面端；它不是单文件离线安装器。

处理：

- 拉取包含修复的最新代码后，`一键唤醒隐士.bat` 默认会跳过 Hermes 外部安装器，不再弹出该界面。
- 需要单独尝试 Hermes 官方安装器时，手动运行 `assets/installers/hermes-desktop-setup.exe`，或执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -InstallHermes
```

- 只有需要把 Hermes 安装失败视为整体验收失败时，才使用 `-RequireHermesInstall`。
- 提交排障信息时，运行 `scripts\collect-logs.ps1`；诊断包会包含 Hermit 主日志和 Hermes bootstrap 日志。

### 运行期配置未完成

现象：

- 日志中出现 `Runtime config not configured`。
- 安装仍然完成，但后续外部 API 或移动端远程控制不可用。

处理：

- 提前复制 `assets/config/runtime.example.json` 为 `assets/config/runtime.local.json`，或使用兼容路径 `assets/config/config.json`，填入真实值后重新安装。
- 或安装后进入 Hermit 项目根目录运行：

```powershell
Set-Location <Hermit项目目录>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1
```

配置文件会写入 `%LOCALAPPDATA%\Hermit\config\runtime.secrets.json`。日志不应包含 API Key、Token 或 Webhook secret。

### TCP 可连但 API 请求失败

现象：

- `Test-NetConnection api.deepseek.com -Port 443` 显示 `TcpTestSucceeded: True`。
- `Invoke-RestMethod` 仍报 `无法连接到远程服务器`。

处理：

- 不要继续手动拼长命令，进入 Hermit 项目根目录运行：

```powershell
Set-Location <Hermit项目目录>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test-api.ps1
```

- 该脚本会读取 `%LOCALAPPDATA%\Hermit\config\runtime.secrets.json`，不打印 API Key，并输出 DNS、TCP、代理、HTTP 状态、响应体和内层异常。
- 如果输出类似 `Proxy: http://127.0.0.1:3067`，并且内层异常提示 `127.0.0.1:3067` 连接被拒绝，说明 Windows 系统代理已开启但本机代理程序未监听该端口。关闭 Windows 代理、启动对应代理程序、修正代理端口，或运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test-api.ps1 -NoProxy
```

- 如果没有 HTTP 状态码，通常是 TLS、证书、代理、防火墙流量检查或 Windows PowerShell/.NET HTTP 栈问题。
- 如果返回 HTTP 400，优先检查 `model`、`baseUrl` 和请求体；如果返回 HTTP 401，优先检查 API Key 是否无效或已撤销。

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
