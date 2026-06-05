# Hermit（隐士）

Hermit 是一个面向 Windows 10/11 普通用户的本地化 AI 办公自动化部署包。它的目标是把 Python 运行环境、离线依赖、Hermes 桌面端配置和 AI Agent 可调用的 `.docx` 文档处理技能打包到一个可离线分发、可重复执行、可排障的项目中。

当前项目已完成工程骨架、文档、资源契约、安全 Word Skill、本机离线资源准备和 dry-run 安装流程；真实安装仍需在干净 Windows 环境验收。

## 核心目标

- 一键安装：用户双击入口文件即可启动安装流程。
- 尽量离线：安装过程从 `assets/` 读取本地安装包和 wheel 包。
- 幂等执行：重复运行不会破坏已安装环境或重复污染 PATH。
- 配置安全：覆盖 Hermes 配置前必须备份，日志不得输出敏感值。
- 文档安全：`.docx` 修改必须另存为修订版，绝不覆盖原文件。
- 可诊断：所有关键步骤写入本地日志并返回明确退出码。

## 当前目录

```text
Hermit_Project/
├── assets/
│   ├── installers/
│   ├── wheels/
│   ├── config/
│   ├── manifest.json
│   └── checksums.sha256
├── hermit_skills/
├── scripts/
├── tests/
├── docs/
├── TODO.md
├── initPrompt.md
└── README.md
```

## 当前状态

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| 项目方案 | 已完成 | 见 `initPrompt.md` |
| 待办清单 | 已创建 | 见 `TODO.md` |
| 安装文档 | 已创建 | 见 `docs/installation.md` |
| 排障文档 | 已创建 | 见 `docs/troubleshooting.md` |
| Word Skill 契约 | 已创建 | 见 `docs/docx-skill-contract.md` |
| 安全 Word Skill 提示词 | 已创建 | 见 `docs/prompts/safe-docx-skill-prompt.md` |
| 安全 Word Skill 实现 | 已创建 | 见 `hermit_skills/docx_processor.py` |
| Word Skill 测试 | 已创建 | 见 `tests/test_docx_processor.py` |
| 开源项目元数据 | 已创建 | MIT License、Security、Contributing、CI |
| 资源校验脚本 | 已创建 | 见 `scripts/verify-assets.ps1` |
| 安装入口 | 已创建 | 见 `一键唤醒隐士.bat` 和 `scripts/install.ps1` |
| 完整安装流程 | 已实现 dry-run | 真实安装尚需在干净 Windows 环境验收 |
| 本地离线资源 | 本机已准备 | Python、Hermes、wheels、config zip 已下载/生成；本地清单不提交 |

## 快速开始

1. 阅读 `initPrompt.md` 了解项目方案。
2. 阅读 `TODO.md` 按阶段推进。
3. 按 `docs/installation.md` 准备离线资源。
4. 运行 `scripts/verify-assets.ps1` 校验资源清单。
5. 运行 `scripts/install.ps1 -DryRun` 验证安装计划，再在干净 Windows 环境做真实安装验收。

当前可以运行的验证命令：

```powershell
python -m unittest discover -s tests -p "test_*.py" -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verify-assets-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install-bootstrap-tests.ps1
```

在离线资源未准备完成前，`scripts/install.ps1` 会返回退出码 `2`，表示安装包尚未就绪，且不会执行任何安装动作。使用 `-DryRun` 可以完整验证安装计划而不触发真实安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1 -DryRun
```

本机已可使用 `assets/manifest.local.json` 和 `assets/checksums.local.sha256` 表示本地离线资源就绪；这些文件被 `.gitignore` 排除，不应提交到公开仓库。`scripts/install.ps1` 会优先读取本地清单，未发现本地清单时回退到公开 bootstrap 清单。

安装日志写入 `%LOCALAPPDATA%\Hermit\logs\`。需要打包排障信息时运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\collect-logs.ps1
```

## 安全原则

- 不把 API Key、Token、Cookie 或真实用户配置提交到仓库。
- 不默认覆盖 Hermes 配置；当前目标为 `%LOCALAPPDATA%\hermes`，覆盖前必须备份，并兼容备份旧 `%APPDATA%\Hermes`。
- 不在日志中打印敏感配置值。
- 不覆盖用户原始 `.docx` 文件。
- AI Word Skill 只能访问 `C:\HermitWorkspace` 沙箱内的 `.docx` 文件。
- Word Skill 写入前必须自动备份到 `.backup`，并且源码不得包含文件删除能力。

## 开源准备

- License：MIT，见 `LICENSE`。
- 安全政策：见 `SECURITY.md`。
- 贡献指南：见 `CONTRIBUTING.md`。
- 发布检查：见 `docs/open-source-release.md`。
- CI：见 `.github/workflows/ci.yml`。

公开仓库不应包含私有安装包、wheel 缓存、真实配置模板、日志、诊断包或用户文档。
