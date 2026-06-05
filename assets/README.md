# Local Assets

This directory separates open-source metadata from local redistributable assets.

## Tracked Files

- `manifest.json`: public bootstrap manifest. It remains `packageReady=false` so a fresh clone does not pretend to be a complete offline package.
- `checksums.sha256`: public checksum file for committed bootstrap installers.
- `installers/python-3.11.9-amd64.exe`: pinned Python installer used for Hermit-managed Python 3.11.
- `installers/hermes-desktop-setup.exe`: pinned Hermes Desktop installer.
- `config/config.example.json`: safe Hermes config example without secrets.
- `config/runtime.example.json`: safe runtime secret config example with empty secret values.

## Local-Only Files

The following files are ignored by git and may exist on a packager machine:

- `manifest.local.json`
- `checksums.local.sha256`
- `wheels/*.whl`
- `config/config_template.zip`
- `config/config.json`
- `config/runtime.local.json`

`scripts/install.ps1` prefers local manifest/checksum files when they exist. The public repository includes pinned installers, but still needs local wheels, config template, and generated local manifests before it is fully offline-ready.
`scripts/configure.ps1` prefers `assets/config/runtime.local.json`, then `assets/config/config.json`, then falls back to interactive prompts.
`scripts/prepare-assets.ps1` can recreate local installers, wheels, config template, manifest, and checksum files on a connected machine.
