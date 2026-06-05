# 安全 Word Skill 实现提示词

本文档是后续实现 `hermit_skills/docx_processor.py` 时可直接喂给 Codex / Cursor 的安全增强提示词。它在原始需求基础上做了工程化收紧：默认工作区固定、接口简单、路径强校验、写前备份、零文件删除、错误脱敏。

## 专业化调整说明

原始提示词方向正确，但需要补强以下边界：

- `file_name` 不应接受任意系统路径。公共接口只接受沙箱内相对 `.docx` 路径，拒绝绝对路径、盘符、UNC、`..`、通配符和空字节。
- `C:\HermitWorkspace` 位于系统盘根目录，创建可能需要管理员权限。实现应自动创建；如果权限不足，返回友好错误，不泄露真实内部路径。
- Windows reparse point、junction、symlink 可能绕过普通路径校验。解析路径时必须检测目标文件及父目录不能是重解析点。
- “抛出 SecurityError”与“所有错误友好输出”需要统一。内部校验可以抛 `SecurityError`，但公开方法必须捕获并返回结构化 dict。
- “零删除权限”应定义为零文件系统删除权限：脚本中不得出现 `os.remove`、`os.unlink`、`Path.unlink`、`shutil.rmtree`、`Remove-Item` 等删除文件或目录的逻辑。
- 为方便 Agent 使用，公共方法应返回 JSON 可序列化 dict，而不是裸字符串。

## 可直接使用的实现提示词

```text
# Role: 高级 Python 安全工程师 & Office 文档自动化专家
# Project: Hermit（隐士）- 安全本地 Word Skill
# Target file: hermit_skills/docx_processor.py

请实现一个面向 AI Agent 调用的安全 Word `.docx` 处理模块。该模块必须方便 Agent 使用，但安全边界优先于功能扩展。

## 核心安全模型

1. 固定沙箱根目录：
   - 默认安全根目录为 `C:\HermitWorkspace`。
   - 模块初始化时如果目录不存在，应自动创建。
   - 自动创建失败时，公共方法返回结构化错误，不泄露真实系统路径。

2. 路径沙箱化：
   - 公共方法参数名使用 `file_name`，只允许传入沙箱内相对 `.docx` 路径。
   - 禁止绝对路径，例如 `C:\Users\...`。
   - 禁止 UNC 路径，例如 `\\server\share\...`。
   - 禁止 `..` 越权。
   - 禁止空字符串、空字节、通配符、非 `.docx` 后缀。
   - 禁止访问沙箱外目录。
   - 禁止跟随会逃逸沙箱的 symlink、junction、reparse point。
   - 任意路径违规都返回：
     - `ok: false`
     - `errorCode: "SECURITY_ERROR"`
     - `message: "SecurityError: 拒绝访问沙箱外文件"`
   - 错误信息绝不能泄露真实系统路径。

3. 纯参数接口：
   - 只暴露安全封装后的白名单方法。
   - 不允许 Agent 传入任意 Python 字符串并执行。
   - 严禁使用 `eval`、`exec`、`compile`、`subprocess` 执行 Agent 输入。

4. 零文件删除权限：
   - 整个脚本严禁出现任何文件或目录删除逻辑。
   - 禁止使用 `os.remove`、`os.unlink`、`Path.unlink`、`shutil.rmtree`。
   - 不要提供清空目录、删除备份、删除原文件等功能。

5. 自动备份：
   - 任意写操作前，必须先把原文件复制到 `C:\HermitWorkspace\.backup\`。
   - 备份文件名使用原始文件名安全化后的 stem、UTC 时间戳和 `.docx` 后缀。
   - 备份成功后才允许写修订文件。
   - 备份失败则中止写操作。

6. 安全回写：
   - 原文件绝不能被覆盖。
   - `safe_update_section` 输出文件应写入沙箱内，并命名为 `原文件名_Hermit修订版.docx`。
   - 如果同名修订文件已存在，应追加时间戳，避免覆盖旧修订版。

## 公共接口

实现类：

```python
class SafeDocxProcessor:
    @staticmethod
    def safe_read(file_name: str) -> dict:
        ...

    @staticmethod
    def safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict:
        ...
```

同时在模块级暴露两个兼容函数：

```python
def safe_read(file_name: str) -> dict:
    return SafeDocxProcessor.safe_read(file_name)

def safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict:
    return SafeDocxProcessor.safe_update_section(file_name, target_heading, new_text)
```

不要暴露 `extract_text(file_path)` 或 `update_section(file_path, ...)` 这类可接收任意系统路径的公共接口。

## `safe_read(file_name)` 行为

- 仅读取沙箱内 `.docx` 文件。
- 返回文档文本和章节结构。
- 返回内容不得包含真实系统绝对路径。

成功返回示例：

```json
{
  "ok": true,
  "file": "proposal.docx",
  "sections": [
    {
      "heading": "实施计划",
      "level": 1,
      "paragraphStart": 5,
      "paragraphEnd": 12,
      "text": "章节正文"
    }
  ],
  "warnings": []
}
```

## `safe_update_section(file_name, target_heading, new_text)` 行为

- 先校验 `file_name` 位于沙箱内。
- 校验 `target_heading` 和 `new_text` 是普通字符串。
- 查找唯一匹配的 Word Heading。
- 标题不存在时失败。
- 标题重复时失败。
- 目标区域含表格、图片、批注、修订痕迹、文本框等复杂内容时，应返回 warning 或拒绝修改。
- 写操作前先备份原文件。
- 修改结果另存为修订版，不覆盖原文件。

成功返回示例：

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

## 错误返回格式

所有公共方法必须捕获异常，并返回如下格式：

```json
{
  "ok": false,
  "errorCode": "SECURITY_ERROR",
  "message": "SecurityError: 拒绝访问沙箱外文件",
  "warnings": []
}
```

错误消息必须对 Agent 友好，不得包含真实系统绝对路径、用户名、环境变量值或堆栈信息。

## 必须覆盖的测试

创建 `tests/test_docx_processor.py`，至少覆盖：

1. `safe_read` 可读取沙箱内普通 `.docx`。
2. `safe_read` 拒绝 `..\secret.docx`。
3. `safe_read` 拒绝绝对路径。
4. `safe_read` 拒绝非 `.docx` 文件。
5. `safe_update_section` 修改前创建 `.backup` 备份。
6. `safe_update_section` 不覆盖原文件。
7. `safe_update_section` 输出修订版文件。
8. 标题不存在时失败。
9. 标题重复时失败。
10. 错误消息不包含真实系统路径。
11. 源码中不存在文件删除 API：`os.remove`、`os.unlink`、`Path.unlink`、`shutil.rmtree`。

请先写测试，再实现代码。实现必须简洁、可审计、无网络访问、无任意代码执行能力。
```

