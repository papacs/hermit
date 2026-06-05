# Hermit 排障手册

本文档记录 Hermit 安装和运行阶段的常见问题、定位方法和预期处理方式。

## 日志位置

安装脚本应将日志写入：

```text
%LOCALAPPDATA%\Hermit\logs\
```

日志文件命名建议：

```text
install-YYYYMMDD-HHMMSS.log
```

## 常见问题

### 资源文件缺失

现象：

- 安装脚本在资源校验阶段中止。
- 输出缺失的文件路径。

处理：

- 按 `docs/installation.md` 准备离线资源。
- 更新 `assets/manifest.json` 和 `assets/checksums.sha256`。

### SHA256 校验失败

现象：

- 校验脚本提示文件哈希不匹配。

处理：

- 删除异常文件。
- 从官方渠道重新下载。
- 重新计算 SHA256 并更新清单。

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

- 安装脚本应使用项目内 Python 3.11.9 安装包。
- 如果选择系统级安装，脚本必须避免重复追加 PATH。

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

