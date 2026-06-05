# Local Assets

This directory separates open-source metadata from local redistributable assets.

## Tracked Files

- `manifest.json`: public offline bootstrap manifest with `packageReady=true`.
- `checksums.sha256`: public checksum file for committed offline bootstrap assets.
- `installers/python-3.11.9-amd64.exe`: pinned Python installer used for Hermit-managed Python 3.11.
- `installers/hermes-desktop-setup.exe`: pinned Hermes Desktop installer.
- `wheels/python_docx-1.2.0-py3-none-any.whl`: pinned python-docx wheel.
- `wheels/lxml-6.1.1-cp311-cp311-win_amd64.whl`: pinned CPython 3.11 Windows x64 lxml wheel.
- `wheels/typing_extensions-4.15.0-py3-none-any.whl`: pinned typing-extensions wheel.
- `config/config_template.zip`: safe Hermes config template without secrets.
- `config/config.example.json`: safe Hermes config example without secrets.
- `config/runtime.example.json`: safe runtime secret config example with empty secret values.

## Local-Only Files

The following files are ignored by git and may exist on a packager machine:

- `manifest.local.json`
- `checksums.local.sha256`
- `config/config.json`
- `config/runtime.local.json`

`scripts/install.ps1` prefers local manifest/checksum files when they exist. Without local manifests, the committed public manifest is already sufficient for offline bootstrap installation.
`scripts/configure.ps1` prefers `assets/config/runtime.local.json`, then `assets/config/config.json`, then falls back to interactive prompts.
`scripts/prepare-assets.ps1` can recreate or refresh local installers, wheels, config template, manifest, and checksum files on a connected machine.
