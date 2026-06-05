# Contributing

Hermit is being prepared as an open-source Windows local automation tool. Contributions should keep the project safe, offline-friendly, and easy to inspect.

## Development Setup

1. Use Python 3.11.
2. Install development dependencies:

```powershell
python -m pip install -e .[dev]
```

3. Run tests:

```powershell
python -m pytest -v
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\verify-assets-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\install-bootstrap-tests.ps1
```

## Pull Request Expectations

- Keep changes focused.
- Add or update tests for behavior changes.
- Do not commit local installer binaries, wheel downloads, secrets, or generated diagnostic archives.
- Update `TODO.md` when changing project status.
- Update docs when changing public behavior or security boundaries.

## Security-Sensitive Changes

Changes touching these areas need extra review:

- `scripts/install.ps1`
- `scripts/verify-assets.ps1`
- `hermit_skills/docx_processor.py`
- `assets/manifest.json`
- Configuration injection logic
- Sandbox or backup behavior

