# Contributing to Yashima

Yashima is a Swift Concurrency-first local artifact cache. Contributions should keep the package small, predictable, and suitable for use as a public Swift Package.

## Development Setup

Requirements:

- Swift 6.3 or later
- macOS 14 or later for local development

Run the test suite:

```sh
swift test
```

## Contribution Guidelines

- Keep the public API small and easy to explain.
- Prefer Swift Concurrency: `async`/`await`, actors, and `Sendable`.
- Do not add GCD, `DispatchQueue`, `OperationQueue`, or `NSOperation` to the package implementation.
- Keep standard convenience APIs as thin wrappers over codec-based APIs.
- Add focused Swift Testing coverage for behavior changes.
- Use synthetic fixtures only. Do not add real app data, private logs, real screenshots, location data, or user-derived artifacts.
- Do not add production credentials, tokens, certificates, provisioning profiles, `.env` files, or local machine details.

## Pull Requests

Before opening a pull request, please make sure:

- `swift test` passes.
- New public behavior is documented.
- New public API is intentional and minimal.
- No private data or secrets are included.
- Any generated artifacts are excluded unless they are intentionally part of the package.

## AI-Assisted Contributions

AI tools are welcome as development aids, but generated changes must be reviewed like ordinary code. Do not paste secrets, private logs, real user data, or local-only planning notes into prompts, issues, pull requests, examples, or tests.

When in doubt, use synthetic examples and leave private context out of the repository.
