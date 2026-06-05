# Hermit 待办事项

本文档按可交付顺序跟踪 Hermit 的推进状态。当前阶段是 bootstrap：先建立工程边界、文档、资源契约和任务顺序，再进入脚本与 Skill 实现。

## 进行中

- [x] Phase 1：工程骨架与文档
  - [x] 创建推荐目录结构。
  - [x] 创建 `README.md`。
  - [x] 创建安装说明、排障说明和 Word Skill 契约文档。
  - [x] 创建资源清单和配置示例骨架。
  - [x] 创建 PowerShell 资源校验脚本 `scripts/verify-assets.ps1`。
  - [x] 创建安全安装入口骨架 `scripts/install.ps1`。
  - [x] 创建日志采集脚本 `scripts/collect-logs.ps1`。

## 下一步

- [x] Phase 2：离线资源准备
  - [x] 下载 Python 3.11.9 Windows x64 安装包到 `assets/installers/`。
  - [x] 下载 Hermes 桌面端安装包到 `assets/installers/`。
  - [x] 使用 `pip download` 生成 `python-docx` 及其依赖 wheel 包。
  - [x] 生成无密钥 `assets/config/config_template.zip`。
  - [x] 生成本机本地清单 `assets/manifest.local.json`。
  - [x] 生成本机本地哈希 `assets/checksums.local.sha256`。
  - [x] 保持公开 `assets/manifest.json` 为 bootstrap 状态，避免开源仓库误提交二进制资源。

- [ ] Phase 3：安装脚本
  - [x] 创建 `一键唤醒隐士.bat`，负责 UAC 提权和调用 PowerShell。
  - [x] 创建 `scripts/install.ps1` bootstrap 骨架，负责日志初始化、资源校验和资源未就绪中止。
  - [x] 支持本地 `manifest.local.json` / `checksums.local.sha256` 优先。
  - [ ] 扩展 `scripts/install.ps1`，负责完整安装流程。
  - [ ] 实现幂等检测、配置备份、失败退出码和安装日志。
  - [ ] 在无网络环境中完成一次端到端验证。

- [x] Phase 4：Word Skill
  - [x] 创建 `hermit_skills/docx_processor.py`。
  - [x] 将安全 Word Skill 提示词固化到 `docs/prompts/safe-docx-skill-prompt.md`。
  - [x] 实现固定沙箱根目录 `C:\HermitWorkspace` 和 `.backup` 自动创建。
  - [x] 实现路径合规校验，拒绝绝对路径、UNC、`..`、通配符、非 `.docx` 和重解析点逃逸。
  - [x] 实现 `SafeDocxProcessor.safe_read(file_name)`。
  - [x] 实现 `SafeDocxProcessor.safe_update_section(file_name, target_heading, new_text)`。
  - [x] 写操作前自动备份到 `C:\HermitWorkspace\.backup\`。
  - [x] 确保源码不包含文件删除 API、`eval`、`exec`、`compile` 或执行 Agent 输入的 `subprocess`。
  - [x] 确保所有公共错误返回 Agent 友好字符串，不泄露真实系统路径。
  - [x] 使用测试动态生成 `.docx` 夹具，避免提交二进制测试文档。
  - [x] 创建 `tests/test_docx_processor.py`。

- [ ] Phase 4.5：开源项目准备
  - [x] 添加 `.gitignore`，排除安装包、wheel、密钥、日志和构建产物。
  - [x] 添加 `LICENSE`。
  - [x] 添加 `SECURITY.md`。
  - [x] 添加 `CONTRIBUTING.md`。
  - [x] 添加 `CHANGELOG.md`。
  - [x] 添加 `pyproject.toml`。
  - [x] 添加 GitHub Actions Windows CI。
  - [x] 添加 `docs/open-source-release.md`。
  - [x] 初始化 git 仓库并创建首个提交。
  - [ ] 确认 GitHub 仓库名、远程地址和默认分支。

- [ ] Phase 5：验收与打包
  - [ ] 验证 Windows 10。
  - [ ] 验证 Windows 11。
  - [ ] 验证未安装 Python 的干净环境。
  - [ ] 验证已有 Python 的环境。
  - [ ] 验证 Hermes 已安装且存在旧配置的环境。
  - [ ] 生成可分发压缩包。

## 风险清单

- Hermes 静默安装参数需要以实际安装包为准验证。
- `%APPDATA%\Hermes` 的真实配置结构需要在目标版本上确认。
- `python-docx` 无法完整覆盖复杂 Word 格式，复杂内容需要拒绝修改或返回 warning。
- 固定沙箱 `C:\HermitWorkspace` 在部分机器上可能需要管理员权限；安装脚本应提前创建并设置当前用户 ACL。
- 当前尚未设置远程仓库，无法推送或打开 PR。
- Hermes 安装包可能不允许随开源仓库再分发，发布前必须确认授权。
