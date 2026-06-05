# Security Policy

Hermit is designed to run local automation on Windows machines. Treat local file access, installer execution, and document rewriting as security-sensitive behavior.

## Supported Versions

The project is currently pre-release. Security fixes are applied to the latest source version only.

## Reporting a Vulnerability

Please do not open a public issue with exploit details. Report privately to the project maintainer once a public repository and contact address are available.

Until then, include the following information in a private report:

- Affected file or script.
- Operating system version.
- Steps to reproduce.
- Expected impact.
- Whether secrets, arbitrary file access, or document overwrite is involved.

## Security Rules

- Do not commit real API keys, tokens, cookies, or private workspace URLs.
- Do not commit private installer packages unless their license permits redistribution.
- Word Skill code must not expose arbitrary filesystem paths to AI agents.
- Word Skill code must not contain file deletion capabilities.
- Installation scripts must back up user configuration before overwriting it.
- Logs must not print secrets or full sensitive configuration values.

