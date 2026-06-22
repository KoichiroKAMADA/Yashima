# Security Policy

Yashima is intended to be a public open-source Swift Package. Security and privacy issues should be handled carefully and, when needed, privately.

## Supported Versions

Yashima is pre-1.0. Security fixes are expected to target the latest public release line.

| Version | Supported |
| ------- | --------- |
| 0.2.x   | Yes, after the first public release |
| < 0.2   | No |

## Reporting a Vulnerability

Please report suspected vulnerabilities through GitHub's private vulnerability
reporting flow for this repository when it is available.

If private vulnerability reporting is not available, please open a public issue
that asks for a private reporting path without including technical details,
proof-of-concept code, private data, or exploit instructions.

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
