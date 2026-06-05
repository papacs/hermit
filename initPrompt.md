# Hermit（隐士）项目方案

Hermit 是一个面向 Windows 普通用户的本地化 AI 办公自动化部署包。核心目标不是“生成几段脚本”，而是交付一个使用本地资源快速稳定安装、可重复安装、可排障、可回滚的轻量系统，让 AI Agent 能在用户本机安全地读取和局部修改 `.docx` 文档。

## 1. 项目定位

### 目标

- 一键启动安装：普通用户双击入口文件即可完成环境检查、依赖安装、配置注入和技能部署。
- 本地资源优先：安装过程优先使用项目内安装包、wheel 包和配置模板，减少下载失败、网络波动和重复等待；真实使用场景默认联网。
- 可重复执行：脚本必须支持重复运行，不因部分组件已安装而失败。
- 安全回写文档：AI 只能基于指定标题锚点修改局部内容，不能覆盖原 `.docx`。
- 可诊断：安装日志、版本信息、失败原因和退出码必须明确，方便后续排障。

### 非目标

- 不做通用 Office 插件。
- 不实现完整 Word 排版引擎。
- 不承诺保留所有复杂 `.docx` 特性，例如宏、批注、修订模式、复杂域代码、嵌套文本框。
- 不把 API Key、Slack Token 等敏感信息明文提交到代码仓库。

## 2. 推荐项目结构

```text
Hermit_Project/
├── assets/
│   ├── installers/
│   │   ├── python-3.11.9-amd64.exe
│   │   └── hermes-desktop-setup.exe
│   ├── wheels/
│   │   ├── python_docx-*.whl
│   │   ├── lxml-*.whl
│   │   └── typing_extensions-*.whl
│   ├── config/
│   │   ├── config_template.zip
│   │   └── config.example.json
│   ├── manifest.json
│   └── checksums.sha256
├── hermit_skills/
│   ├── docx_processor.py
│   └── __init__.py
├── scripts/
│   ├── install.ps1
│   ├── verify-assets.ps1
│   └── collect-logs.ps1
├── tests/
│   ├── fixtures/
│   │   ├── simple_sections.docx
│   │   └── table_and_heading.docx
│   └── test_docx_processor.py
├── docs/
│   ├── installation.md
│   ├── troubleshooting.md
│   └── docx-skill-contract.md
├── 一键唤醒隐士.bat
└── README.md
```

## 3. 本地安装资源规范

`assets/manifest.json` 应记录所有本地安装资源的名称、版本、来源、用途和 SHA256。安装前必须先校验 `checksums.sha256`，校验失败应立即中止。

示例字段契约：

```json
{
  "python": {
    "version": "3.11.9",
    "file": "assets/installers/python-3.11.9-amd64.exe",
    "source": "https://www.python.org/downloads/windows/",
    "sha256": "64位小写十六进制SHA256"
  },
  "hermes": {
    "version": "固定到实际分发版本",
    "file": "assets/installers/hermes-desktop-setup.exe",
    "source": "Hermes官方发布地址",
    "sha256": "64位小写十六进制SHA256"
  },
  "pythonPackages": [
    {
      "name": "python-docx",
      "version": "固定到实际wheel版本",
      "filePattern": "assets/wheels/python_docx-*.whl"
    }
  ]
}
```

真实打包时，`manifest.json` 必须由打包人员或打包脚本写入实际版本和实际哈希；安装脚本不得接受缺失、空值或非 SHA256 格式的记录。

本地 wheel 包生成建议：

```powershell
py -3.11 -m pip download `
  --dest assets/wheels `
  --only-binary=:all: `
  python-docx
```

## 4. 安装架构

### 推荐策略

优先采用“项目私有运行时”策略，把 Python 运行环境放到 `%LOCALAPPDATA%\Hermit\runtime\`，减少对系统 Python 和全局 PATH 的污染。只有当 Hermes 或目标环境明确要求全局 Python 时，才启用系统级 Python 安装。

### 安装流程

1. `一键唤醒隐士.bat` 负责：
   - 定位项目根目录。
   - 请求管理员权限。
   - 使用 `ExecutionPolicy Bypass` 调用 `scripts/install.ps1`。
   - 保留窗口，显示最终成功或失败信息。

2. `scripts/install.ps1` 负责：
   - 初始化日志目录：`%LOCALAPPDATA%\Hermit\logs\install-YYYYMMDD-HHMMSS.log`。
   - 校验 `assets/manifest.json` 和 `assets/checksums.sha256`。
   - 检测 Windows 版本、PowerShell 版本和 CPU 架构。
   - 检测 Python 版本；优先复用满足条件的 Python，否则安装或准备本地 runtime。
   - 使用 `--no-index --find-links assets/wheels` 从本地 wheel 安装依赖。
   - 静默安装 Hermes，并校验安装结果。
   - 备份现有 `%LOCALAPPDATA%\hermes` 配置到 `%LOCALAPPDATA%\Hermit\backup\hermes-YYYYMMDD-HHMMSS`，并兼容备份旧 `%APPDATA%\Hermes`。
   - 注入配置模板；能合并则合并，不能合并时必须先备份再覆盖。
   - 复制 `hermit_skills/` 到 `%USERPROFILE%\Hermit_Skills\`。
   - 运行安装后自检，包括 Python import、Hermes 路径、技能脚本可执行性。

### 幂等要求

- 重复执行安装脚本不能重复污染 PATH。
- 已安装组件版本满足要求时跳过安装。
- 配置注入前必须备份。
- 技能脚本复制应使用版本或文件哈希判断是否更新。
- 任意失败都要返回非零退出码，并写入明确错误信息。

## 5. 配置与安全

`config_template.zip` 不应默认包含真实密钥。推荐放置占位模板，并在安装后由用户本机填写或由专门的本地初始化脚本写入。

如确需分发带密钥的私有安装包，必须满足：

- 安装包只在可信范围内传递。
- 密钥文件不进入 git。
- 配置文件落盘后设置当前用户可读写 ACL。
- 日志中禁止输出 API Key、Token、Cookie 等敏感值。
- 配置注入前后都保留备份和校验记录。

## 6. Word Skill 设计

`hermit_skills/docx_processor.py` 是 AI Agent 调用的核心工具，必须采用沙箱化安全接口。默认安全根目录为 `C:\HermitWorkspace`，Agent 只能通过相对文件名访问沙箱内 `.docx` 文件。

```python
safe_read(file_name: str) -> dict
safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict
```

不得暴露 `extract_text(file_path)` 或 `update_section(file_path, ...)` 这类可接收任意系统路径的公共接口。

### `safe_read`

返回结构化结果，而不是只返回纯文本：

```json
{
  "ok": true,
  "file": "example.docx",
  "sections": [
    {
      "heading": "一、项目背景",
      "level": 1,
      "paragraphStart": 3,
      "paragraphEnd": 8,
      "text": "..."
    }
  ],
  "warnings": []
}
```

这样 Agent 修改前能明确知道可修改锚点，避免凭空猜标题。

### `safe_update_section`

核心原则：

- 不修改原文件。
- 写操作前先备份原文件到 `C:\HermitWorkspace\.backup\`。
- 输出文件名固定为：`原文件名_Hermit修订版.docx`；如已存在则追加时间戳。
- 只允许修改命中的标题区域。
- 标题不存在、标题重复、目标区域为空时必须失败并返回结构化错误。
- 路径必须经过沙箱校验，拒绝绝对路径、UNC、`..`、空字节、通配符、非 `.docx` 后缀和 reparse point 逃逸。
- 公共错误信息不能泄露真实系统路径。
- 源码中不得出现 `os.remove`、`os.unlink`、`Path.unlink`、`shutil.rmtree` 等文件删除 API。
- 默认仅替换普通段落文本；遇到表格、图片、批注、修订痕迹时应返回 warning 或拒绝修改。
- 保留标题段落和标题样式。
- 尽量复用目标区域首个正文段落的样式写入新内容。

返回示例：

```json
{
  "ok": true,
  "file": "proposal.docx",
  "backup": ".backup/proposal_20260605T021500Z.docx",
  "output": "proposal_Hermit修订版.docx",
  "targetHeading": "实施计划",
  "changedParagraphs": 4,
  "warnings": []
}
```

## 7. 测试与验收标准

### 安装验收

- Windows 10 和 Windows 11 均可运行。
- 联网真实使用环境下可完成安装和后续调用验证。
- Python 未安装时可完成安装。
- Python 已安装且版本满足要求时不会重复安装。
- Python 已安装但版本过低时能给出明确处理策略。
- Hermes 已安装时不会破坏现有配置。
- 配置覆盖前能生成备份。
- 任一安装包缺失或校验失败时能中止并提示缺失文件。

### Skill 验收

- 能提取普通标题结构文档。
- 能修改指定一级或二级标题下的正文。
- 标题不存在时失败，且不生成修订文件。
- 标题重复时失败，要求用户提供更精确锚点。
- 原文件被 Word 占用时失败并返回明确错误。
- `..\secret.docx`、绝对路径、UNC 路径、非 `.docx` 文件必须返回 `SECURITY_ERROR` 或 `INVALID_INPUT`。
- 所有错误消息不得包含真实系统路径。
- 写操作前必须生成 `.backup` 备份。
- 修改后原文件哈希不变。
- 修改后输出文件可被 Word 正常打开。

## 8. 实施阶段建议

### Phase 1：工程骨架

- 建立目录结构。
- 编写 manifest 和 checksum 校验脚本。
- 编写基础安装入口和日志机制。

### Phase 2：本地 Python 与依赖

- 完成 Python 检测。
- 完成本地 wheel 安装。
- 增加 import 自检。

### Phase 3：Hermes 安装与配置

- 完成 Hermes 静默安装。
- 完成配置备份、注入和回滚。

### Phase 4：Word Skill

- 完成安全提示词：`docs/prompts/safe-docx-skill-prompt.md`。
- 完成 `safe_read`。
- 完成 `safe_update_section`。
- 建立 `.docx` 测试样例和 pytest 测试。

### Phase 5：打包与验收

- 完成 README、安装说明、排障文档。
- 在干净 Windows 虚拟机中验证完整安装，并在可联网环境验证外部 API、Hermes 和移动端远程控制链路。

## 9. 可直接喂给 Codex / Cursor 的开工提示词

```text
# Role: 高级 Python 开发工程师 & Windows 自动化部署专家
# Project: Hermit（隐士）- 本地化 AI 办公自动化部署包

你正在实现一个面向 Windows 10/11 普通用户的本地化部署项目。项目目标是：一键安装 Python 运行环境、本地 wheel 依赖、Hermes 桌面端，注入 Hermes 配置模板，并部署 AI Agent 可调用的 `.docx` 文档处理技能。真实使用默认联网，会调用外部 API、Hermes 和移动端远程控制链路。

请严格按生产工程标准实现，不要只生成演示脚本。

## 全局约束

1. 安装过程必须优先使用 `assets/` 本地资源，避免把网络下载作为安装成功的关键路径。
2. 所有安装包和 wheel 包都必须从 `assets/` 读取。
3. 安装脚本必须幂等，重复运行不能破坏已有环境。
4. 所有关键操作必须写入日志。
5. 任何配置覆盖前必须备份。
6. 不允许在日志中输出 API Key、Token、Cookie 等敏感信息。
7. 任意失败必须返回非零退出码，并输出可诊断的中文错误信息。
8. `.docx` 修改必须另存为修订版，绝不能覆盖原文件。

## 请先输出你的实现计划

先阅读并遵循以下目标结构：

Hermit_Project/
├── assets/
│   ├── installers/
│   ├── wheels/
│   ├── config/
│   ├── manifest.json
│   └── checksums.sha256
├── hermit_skills/
│   ├── docx_processor.py
│   └── __init__.py
├── scripts/
│   ├── install.ps1
│   ├── verify-assets.ps1
│   └── collect-logs.ps1
├── tests/
├── docs/
├── 一键唤醒隐士.bat
└── README.md

输出计划后，再按以下任务实现。

## Task 1: 创建安装入口

创建 `一键唤醒隐士.bat`：

- 自动定位自身所在目录。
- 检查管理员权限；没有权限时请求 UAC 提权重新运行。
- 使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass` 调用 `scripts/install.ps1`。
- 保留窗口显示安装结果。

## Task 2: 创建资源校验脚本

创建 `scripts/verify-assets.ps1`：

- 读取 `assets/checksums.sha256`。
- 对所有声明文件计算 SHA256。
- 文件缺失或哈希不匹配时失败。
- 输出中文错误信息和非零退出码。

## Task 3: 创建主安装脚本

创建 `scripts/install.ps1`：

- 初始化日志目录 `%LOCALAPPDATA%\Hermit\logs\`。
- 调用 `verify-assets.ps1`。
- 检测 Windows、PowerShell、CPU 架构。
- 检测 Python >= 3.10。
- 如无可用 Python，使用 `assets/installers/python-3.11.9-amd64.exe` 静默安装，参数必须清晰可维护。
- 使用本地 `assets/wheels/` 安装 `python-docx` 及其依赖：`python -m pip install --no-index --find-links assets/wheels python-docx`。
- 静默安装 `assets/installers/hermes-desktop-setup.exe`。
- 备份 `%LOCALAPPDATA%\hermes` 到 `%LOCALAPPDATA%\Hermit\backup\`，并兼容备份旧 `%APPDATA%\Hermes`。
- 解压并注入 `assets/config/config_template.zip`。
- 复制 `hermit_skills/` 到 `%USERPROFILE%\Hermit_Skills\`。
- 执行安装后自检。

## Task 4: 创建 Word Skill

创建 `hermit_skills/docx_processor.py`：

- 暴露 `safe_read(file_name: str) -> dict`。
- 暴露 `safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict`。
- 不暴露任何可接收任意系统路径的公共方法。
- `safe_read` 返回结构化 sections，包含 heading、level、paragraphStart、paragraphEnd、text。
- `safe_update_section` 只能修改唯一命中的 heading 区域。
- 所有文件访问必须限制在 `C:\HermitWorkspace` 沙箱内。
- 写操作前必须备份到 `C:\HermitWorkspace\.backup\`。
- 源码中不得出现文件删除 API 或任意代码执行 API。
- 标题不存在、标题重复、文件被占用、格式损坏时返回结构化错误。
- 修改结果另存为 `原文件名_Hermit修订版.docx`。
- 原文件绝不能被覆盖。
- 保留标题段落和其余文档内容。
- 对复杂内容，例如表格、图片、批注、修订痕迹，必须返回 warnings 或拒绝修改。

## Task 5: 创建测试

创建 `tests/test_docx_processor.py`：

- 测试提取标题结构。
- 测试成功修改指定标题下的正文。
- 测试标题不存在。
- 测试标题重复。
- 测试原文件不会被修改。
- 测试输出文件可重新打开。

## Task 6: 创建文档

创建：

- `README.md`
- `docs/installation.md`
- `docs/troubleshooting.md`
- `docs/docx-skill-contract.md`

文档必须说明本地安装资源准备方式、安装步骤、常见失败原因、敏感配置处理方式和 `.docx` Skill 的能力边界。

请按任务顺序输出代码。不要省略错误处理、日志、路径转义、中文提示和测试。
```
