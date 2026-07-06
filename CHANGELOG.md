# Changelog

All notable changes to Yashima are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Yashima uses semantic Git tags for releases.

## [Unreleased]

### Added

- DocC documentation catalog for Swift Package Index hosted documentation.
- Swift Package Index manifest.
- Comparison guide, benchmark harness, and `llms.txt` discovery index.
- README badges and explicit "When Not to Use Yashima" guidance.

## [0.5.0] - 2026-06-29

### Added

- `CacheKey.stableIdentifier`, a key-only stable opaque string for external
  labels, auxiliary file names, and deduplication contexts.

### Changed

- README installation and AI-agent planning examples now point at the `0.5.x`
  release line.
- Public docs clarify that `stableIdentifier` is not a storage entry identifier;
  effective cache entries still depend on both `CacheKey` and
  `CacheCodec.identifier`.

## [0.4.0] - 2026-06-23

### Added

- `CompressedDataCodec`, an explicit LZFSE-compressed `Data` codec for large
  text-like generated artifacts such as rendered HTML, JSON, manifests, and
  summaries.
- Tests for compressed-data round trips, codec identity separation, and corrupt
  compressed payload handling.

### Changed

- README installation guidance moved to the `0.4.x` release line.

## [0.3.0] - 2026-06-22

### Added

- `YCache.Options.uiLifecycle` for SwiftUI `List`, `LazyVGrid`, `.task(id:)`,
  and other caller-lifetime-bound workloads.
- Single-flight and cancellation behavior for optional generation APIs.
- Documentation for video thumbnails, PhotoKit thumbnails, SwiftUI lifecycle
  usage, and small `Codable` derived values.

### Changed

- Optional generation now shares concurrent miss work while preserving the rule
  that `nil`, `CancellationError`, and thrown failures are not stored.
- Storage metadata schema remained compatible with `0.2.x`.

## [0.2.0] - 2026-06-22

### Added

- First public-ready release of the Swift Concurrency-first local artifact
  cache.
- Async/await cache API with stable cache identity based on cache keys and codec
  identifiers.
- Memory and disk cache layers with configurable budgets and lifecycle
  operations.
- Single-flight request coalescing with cancellation-aware options for UI-bound
  workloads.
- Standard conveniences for images, `Data`, and `Codable` values built on the
  codec-based core.
- Yashima Preview Lab sample app and stress runner.
- Public documentation, security policy, contribution guide, and Swift Package
  Manager installation guidance.

## [0.1.0] - 2026-06-15

### Added

- Initial Yashima package bootstrap.
- Core cache engine, `CacheKey`, codec protocol, standard codecs, memory store,
  storage store, public `YCache` API, tests, CI, MIT license, and initial public
  documentation.

[Unreleased]: https://github.com/KoichiroKAMADA/Yashima/compare/0.5.0...HEAD
[0.5.0]: https://github.com/KoichiroKAMADA/Yashima/releases/tag/0.5.0
[0.4.0]: https://github.com/KoichiroKAMADA/Yashima/releases/tag/0.4.0
[0.3.0]: https://github.com/KoichiroKAMADA/Yashima/releases/tag/0.3.0
[0.2.0]: https://github.com/KoichiroKAMADA/Yashima/releases/tag/0.2.0
[0.1.0]: https://github.com/KoichiroKAMADA/Yashima/tree/0.1.0
