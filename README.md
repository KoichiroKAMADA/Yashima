# Yashima

<p align="center">
  <img src="Documentation/Assets/yashima-hero.png" alt="Yashima" width="840">
</p>

A Swift Concurrency-first get-or-generate cache for locally generated app artifacts.

Not an image downloader. Not a database.

Yashima is being designed for expensive local results that are safe to regenerate: thumbnails, previews, rendered charts, waveforms, summaries, and other derived artifacts.

## Basic Usage

```swift
let cache = YCache(
    storageDirectory: cacheDirectory,
    storageMaximumByteCount: 200 * 1024 * 1024
)

let thumbnails = cache.using(ImageCodec.jpeg(quality: 0.85))

let thumbnail = try await cache.jpeg(for: key) {
    try await renderThumbnail()
}

let summary: Summary = try await cache.codable(for: key) {
    try await calculateSummary()
}
```

The public face should stay simple. Internally, standard conveniences are thin wrappers over codec-based APIs.

`YCache` is the root type. The `Y` comes from Yashima; supporting vocabulary stays descriptive with names like `CacheKey` and `CacheCodec`.

Image conveniences cache platform images as explicit PNG or JPEG data. On iOS they accept and return `UIImage`; on macOS they accept and return `NSImage`. The codec stores platform images through a small Sendable wrapper when used directly. The default JPEG quality is `0.85`.

The codec-based core API is available first:

```swift
let cache = YCache(storageDirectory: cacheDirectory)
let reports = cache.using(ReportCodec())

let report = try await reports.value(for: key) {
    try await renderReport()
}

let immediate = try await reports.peek(for: key)
```

## Cache Lifecycle

Yashima caches values that are safe to regenerate, so cache lifecycle operations
are explicit and small:

```swift
let metadata = try await cache.metadata(for: key, codec: ImageCodec.jpeg())
let isCached = try await cache.contains(for: key, codec: ImageCodec.jpeg())

try await cache.remove(for: key, codec: ImageCodec.jpeg())
try await cache.removeAll(in: "thumbnails")

let usage = try await cache.storageUsage()
try await cache.trimStorageIfNeeded()
```

Storage entries are trimmed by least-recently-used metadata when
`storageMaximumByteCount` is configured. Storage hits update their access time.
Use `CacheKey.variant(_:_:)` and `CacheKey.version(_:_:)` to describe the inputs
that make a generated artifact unique; Yashima hashes the canonical key and codec
identity internally.

`metadata(for:codec:)` and `contains(for:codec:)` are lightweight lookups. They
do not decode the payload or prove that a later content digest check will
succeed. `storageUsage()` is based on stored metadata and may clean up invalid
metadata or missing data files, but it does not read and hash every payload.

The default read failure policy treats corrupt cache files as misses so callers
can regenerate disposable artifacts. Use `readFailurePolicy: .throwError` when a
caller needs strict error propagation. For writes,
`writeFailurePolicy: .bestEffort` returns the generated value and falls back to
memory-only caching if storage persistence fails.

## Example App

An iOS sample app is available in
[`Examples/YashimaPreviewLab`](Examples/YashimaPreviewLab).

It generates preview artwork inside the app, caches the generated result, and
shows whether each read came from generation, memory, or storage. The sample is
designed to demonstrate Yashima as a cache for locally generated app artifacts,
not as a web image downloader.

## Status

The cache identity, memory store, storage store, core engine, codec-based `YCache` public API, standard codecs, lifecycle APIs, storage trimming, failure policies, and README-first convenience helpers are implemented with Swift Testing coverage.

## Design Notes

- Swift Concurrency-first public API.
- L1 memory cache + L2 storage cache.
- Get-or-generate as the primary usage model.
- Data-first storage with typed codecs.
- `CacheKey` + codec identifier as the effective cache entry identity.
- Explicit invalidation, storage usage, and quota-based storage trimming.
- Cache semantics: values may disappear, but values returned by the cache must match their key, codec, and metadata.

## Requirements

- Swift 6.1 or later
- iOS 16+
- macOS 13+

## Contributing

Yashima is being prepared as a public Swift Package. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before contributing.

## License

Yashima is available under the MIT license. See [LICENSE](LICENSE).
