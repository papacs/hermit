# Offline Assets

This directory separates open-source metadata from local redistributable assets.

## Tracked Files

- `manifest.json`: public bootstrap manifest. It remains `packageReady=false` so a fresh clone does not pretend to contain private binaries.
- `checksums.sha256`: public bootstrap checksum file. It contains no active binary records by default.
- `config/config.example.json`: safe example config without secrets.

## Local-Only Files

The following files are ignored by git and may exist on a packager machine:

- `manifest.local.json`
- `checksums.local.sha256`
- `installers/python-3.11.9-amd64.exe`
- `installers/hermes-desktop-setup.exe`
- `wheels/*.whl`
- `config/config_template.zip`

`scripts/install.ps1` prefers local manifest/checksum files when they exist. Public repositories should not commit local binaries, private config templates, or generated local manifests.

