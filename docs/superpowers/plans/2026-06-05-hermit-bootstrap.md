# Hermit Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Hermit project skeleton, documentation, offline resource contract, and first implementation sequence.

**Architecture:** The project is organized around local Windows deployment assets, PowerShell automation scripts, and Python-based Word skills. Bootstrap work creates stable documents and resource contracts first, then script implementation can proceed against those contracts.

**Tech Stack:** Markdown, JSON, PowerShell, Python 3.11, python-docx, pytest.

---

### Task 1: Bootstrap Documentation

**Files:**
- Create: `TODO.md`
- Create: `README.md`
- Create: `docs/installation.md`
- Create: `docs/troubleshooting.md`
- Create: `docs/docx-skill-contract.md`

- [x] **Step 1: Create the project TODO**

Create `TODO.md` with ordered phases: engineering skeleton, offline resources, install scripts, Word Skill, acceptance packaging.

- [x] **Step 2: Create the README**

Create `README.md` with the project goal, current status, directory layout, safety rules, and next steps.

- [x] **Step 3: Create installation documentation**

Create `docs/installation.md` with the target install flow, offline asset locations, wheel download command, config guidance, and checksum format.

- [x] **Step 4: Create troubleshooting documentation**

Create `docs/troubleshooting.md` with log path, resource failures, checksum failures, PowerShell policy issues, Python version issues, Hermes config restore, and Word file lock handling.

- [x] **Step 5: Create Word Skill contract**

Create `docs/docx-skill-contract.md` defining `safe_read(file_name: str) -> dict`, `safe_update_section(file_name: str, target_heading: str, new_text: str) -> dict`, structured responses, sandbox rules, backup rules, complex content policy, and error codes.

- [x] **Step 6: Verify docs are readable**

Run: `Get-Content -Encoding UTF8 README.md | Select-Object -First 5`

Expected: The first lines render as readable Chinese Markdown.

### Task 2: Resource Contract

**Files:**
- Create: `assets/manifest.json`
- Create: `assets/checksums.sha256`
- Create: `assets/config/config.example.json`

- [x] **Step 1: Create manifest**

Create `assets/manifest.json` with `packageReady: false`, required installer entries, Python package entries, and config entries. Use explicit expected filenames instead of wildcard-only references.

- [x] **Step 2: Create checksum file**

Create `assets/checksums.sha256` with comments documenting the checksum line format.

- [x] **Step 3: Create config example**

Create `assets/config/config.example.json` with safe empty values and a note that real secrets must not be committed.

- [x] **Step 4: Verify JSON parses**

Run: `Get-Content -Raw -Encoding UTF8 assets/manifest.json | ConvertFrom-Json | Select-Object packageReady`

Expected: PowerShell prints `packageReady` as `False`.

### Task 3: Asset Verification Script

**Files:**
- Create: `scripts/verify-assets.ps1`

- [x] **Step 1: Write script behavior**

Implement `scripts/verify-assets.ps1` so it reads `assets/checksums.sha256`, skips blank/comment lines, validates each `<sha256>  <relative-path>` record, checks file existence, calculates SHA256, and exits non-zero on mismatch.

- [x] **Step 2: Run against bootstrap checksum file**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/verify-assets.ps1`

Expected: PASS when the checksum file contains no active records.

### Task 4: Install Entry Skeleton

**Files:**
- Create: `一键唤醒隐士.bat`
- Create: `scripts/install.ps1`
- Create: `scripts/collect-logs.ps1`

- [x] **Step 1: Create bat entry**

Implement UAC elevation and call `scripts/install.ps1` through `powershell.exe -NoProfile -ExecutionPolicy Bypass`.

- [x] **Step 2: Create install script skeleton**

Implement root path detection, log initialization, asset verification call, environment checks, and clear non-zero failure handling.

- [x] **Step 3: Create log collector**

Implement `scripts/collect-logs.ps1` to zip `%LOCALAPPDATA%\Hermit\logs\` into a timestamped diagnostic archive.

### Task 5: Word Skill Test First

**Files:**
- Create: `tests/test_docx_processor.py`
- Create: `hermit_skills/docx_processor.py`
- Create: `hermit_skills/__init__.py`

- [x] **Step 1: Write tests**

Write pytest tests covering title extraction, successful section update, missing heading, duplicate heading, original file hash preservation, and output file reopen.

- [x] **Step 2: Run tests to verify initial failure**

Run: `python -m pytest tests/test_docx_processor.py -v`

Expected: FAIL because `hermit_skills/docx_processor.py` is not implemented yet.

- [x] **Step 3: Implement minimal Skill**

Implement `safe_read` and `safe_update_section` according to `docs/docx-skill-contract.md`.

- [x] **Step 4: Run tests to verify pass**

Run: `python -m pytest tests/test_docx_processor.py -v`

Expected: PASS for all Word Skill tests.
