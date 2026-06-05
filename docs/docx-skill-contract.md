# Word Skill 契约

Hermit 的 Word Skill 面向 AI Agent 调用，目标是安全读取和局部修改 `.docx` 文档。它不是完整 Word 排版引擎。安全边界优先于功能扩展：Agent 只能访问固定沙箱目录中的 `.docx` 文件，不能传入任意系统路径。

## 模块

```text
hermit_skills/docx_processor.py
```

## 沙箱模型

- 默认安全根目录为 `C:\HermitWorkspace`。
- 测试或受控部署可通过进程环境变量 `HERMIT_WORKSPACE_ROOT` 改写沙箱根目录；该值不是 Agent 公共接口参数。
- 模块应在需要时自动创建沙箱目录和 `.backup` 目录。
- 公共接口只接受沙箱内相对 `.docx` 路径。
- 禁止绝对路径、UNC 路径、`..` 越权、空字节、通配符和非 `.docx` 后缀。
- 禁止跟随会逃逸沙箱的 symlink、junction、reparse point。
- 任意路径违规都返回 `SECURITY_ERROR`，消息固定为 `SecurityError: 拒绝访问沙箱外文件`。
- 错误消息不得包含真实系统绝对路径、用户名、环境变量值或堆栈信息。

## 公共接口

```python
class SafeDocxProcessor:
    @staticmethod
    def safe_read(file_name: str) -> dict: ...

    @staticmethod
    def safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict: ...

safe_read(file_name: str) -> dict
safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict
```

不得暴露 `extract_text(file_path)` 或 `update_section(file_path, ...)` 这类可接收任意系统路径的公共接口。

## `safe_read`

读取 `.docx` 并返回结构化章节信息。

成功返回：

```json
{
  "ok": true,
  "file": "example.docx",
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

失败返回：

```json
{
  "ok": false,
  "errorCode": "DOCX_OPEN_FAILED",
  "message": "无法打开文档",
  "warnings": []
}
```

## `safe_update_section`

`safe_update_section` 基于唯一标题锚点替换该标题下的正文，并另存为修订版。任何写操作前必须先把原文件复制到 `C:\HermitWorkspace\.backup\`。

成功返回：

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

## 修改规则

- 原文件绝不能被覆盖。
- 输出文件名固定为 `原文件名_Hermit修订版.docx`。
- 如果同名修订版已存在，应追加时间戳，避免覆盖旧修订版。
- 写入修订版前必须先创建 `.backup` 备份。
- 备份失败时不得继续写入。
- 标题必须唯一匹配。
- 标题不存在时失败。
- 标题重复时失败。
- 保留标题段落。
- 保留目标区域之外的段落。
- 默认仅处理普通段落文本。
- 源码中不得出现文件或目录删除逻辑，例如 `os.remove`、`os.unlink`、`Path.unlink`、`shutil.rmtree`。
- 不得使用 `eval`、`exec`、`compile` 或 `subprocess` 执行 Agent 输入。

## 复杂内容策略

遇到以下内容时，Skill 应返回 warning 或拒绝修改：

- 表格。
- 图片。
- 页眉页脚。
- 批注。
- 修订痕迹。
- 文本框。
- 宏。
- 复杂域代码。

## 错误码

| 错误码 | 含义 |
| --- | --- |
| `FILE_NOT_FOUND` | 文件不存在 |
| `SECURITY_ERROR` | 路径越权或路径不合规 |
| `INVALID_INPUT` | 参数为空、类型错误或后缀不允许 |
| `DOCX_OPEN_FAILED` | 文档无法打开或格式损坏 |
| `HEADING_NOT_FOUND` | 未找到目标标题 |
| `HEADING_NOT_UNIQUE` | 目标标题不唯一 |
| `UNSUPPORTED_COMPLEX_CONTENT` | 目标区域包含不支持的复杂内容 |
| `BACKUP_FAILED` | 写操作前备份失败 |
| `OUTPUT_WRITE_FAILED` | 修订版写入失败 |

## 实现提示词

安全实现提示词保存在：

```text
docs/prompts/safe-docx-skill-prompt.md
```
