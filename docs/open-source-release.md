# Open Source Release Checklist

Hermit is intended to be published as an open-source local automation tool. Before publishing a public repository, complete this checklist.

## Repository Hygiene

- Initialize git only after confirming the final repository name and remote.
- Keep `assets/installers/`, `assets/wheels/`, `assets/config/config_template.zip`, `assets/config/runtime.local.json`, `assets/config/config.json`, logs, diagnostics, and local secrets out of git.
- Confirm `.gitignore` excludes private binaries and generated packages.
- Confirm `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, and `README.md` are present.
- Confirm no real API keys, Slack tokens, cookies, private URLs, or user documents are committed.
- Confirm `assets/manifest.local.json`, `assets/checksums.local.sha256`, installers, wheels, `config_template.zip`, `runtime.local.json`, and `config.json` are not committed.

## Legal And Redistribution

- Python installers should be downloaded by packagers from the official Python distribution channel.
- Hermes redistribution rights must be confirmed before bundling its installer in a public release artifact.
- If a third-party installer cannot be redistributed, document the expected filename and download source instead of committing the binary.
- Wheel packages should be generated from public package indexes or trusted internal mirrors, with hashes recorded in `assets/checksums.sha256`.

## Security Gate

- Run all tests locally on Windows.
- Confirm `hermit_skills/docx_processor.py` does not expose arbitrary system paths.
- Confirm Word Skill write operations create backups before revisions.
- Confirm source code does not contain file deletion APIs in the Word Skill.
- Confirm logs do not include secrets.
- Confirm install scripts do not overwrite Hermes config without backup.

## Suggested First Public Release Scope

- Documentation and project skeleton.
- Resource verification script.
- Install bootstrap script that safely refuses to install while `packageReady=false`.
- Safe Word Skill with tests.
- CI workflow for Windows.

Do not publish an end-user binary installer until the Hermes installer behavior, config path, and redistribution terms are confirmed.
