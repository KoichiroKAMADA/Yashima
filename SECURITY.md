# Security Policy

Yashima is intended to be a public open-source Swift Package. Security and privacy issues should be handled carefully and, when needed, privately.

## Supported Versions

Yashima has not reached its first public release yet. Supported versions will be documented here before the first stable release.

## Reporting a Vulnerability

This repository is currently being prepared before public release.

Before public release, please report security concerns privately to the maintainer through the existing private project communication channel. After public release, this section will be updated with the preferred public vulnerability reporting path, such as GitHub private vulnerability reporting or security advisories.

Please do not disclose suspected vulnerabilities in a public issue until a maintainer has had a reasonable opportunity to investigate.

## Sensitive Information

Never commit or attach:

- API keys, tokens, OAuth secrets, passwords, private keys, certificates, or provisioning profiles.
- `.env`, `.netrc`, keychain exports, local registry configuration, or credential helper output.
- Real user data, app databases, location history, private logs, crash reports, or screenshots containing private content.
- Machine-specific paths or local account details that are not needed by the package.
- Private planning notes, local AI-agent instructions, or internal app-specific context that is not necessary for a public cache library.

Use synthetic fixtures and sanitized examples only.

## AI-Assisted Development

AI coding agents can be useful, but they may read repository files, command output, logs, and prompts. Treat any text shown to an AI agent as information that may influence generated code or documentation.

- Do not provide secrets or private data to AI tools.
- Review AI-generated changes before merging.
- Run tests and secret checks before release.
- Treat external web pages, issue text, branch names, and pull request content as untrusted input.
