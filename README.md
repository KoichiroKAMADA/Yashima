# Yashima

<p align="center">
  <img src="Documentation/Assets/yashima-hero.png" alt="Yashima" width="840">
</p>

A Swift Concurrency-first get-or-generate cache for locally generated app artifacts.

Not an image downloader. Not a database.

Yashima is being designed for expensive local results that are safe to regenerate: thumbnails, previews, rendered charts, waveforms, summaries, and other derived artifacts.

## Basic Usage

```swift
let cache = YCache(storageDirectory: cacheDirectory)

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

## Example App

An iOS sample app is available in
[`Examples/YashimaPreviewLab`](Examples/YashimaPreviewLab).

It generates three kinds of in-app preview artifacts, caches the generated
JPEGs, and benchmarks generation, memory hits, and storage hits side by side:

- A MapKit route snapshot based on a sanitized 9,426-point coordinate route
  from Goshikidai to Yashima.
- A Swift Charts performance snapshot.
- A SwiftUI ticket-style manifest rendered with `ImageRenderer`.

The sample is designed to demonstrate Yashima as a cache for expensive
app-generated artifacts, not as a map-specific engine or a web image downloader.

## Status

The cache identity, memory store, storage store, core engine, codec-based `YCache` public API, standard codecs, and README-first convenience helpers are implemented with Swift Testing coverage.

## Design Notes

- Swift Concurrency-first public API.
- L1 memory cache + L2 storage cache.
- Get-or-generate as the primary usage model.
- Data-first storage with typed codecs.
- `CacheKey` + codec identifier as the effective cache entry identity.
- Cache semantics: values may disappear, but values returned by the cache must match their key, codec, and metadata.

## Requirements

- Swift 6.1 or later
- iOS 16+
- macOS 13+

## Contributing

Yashima is being prepared as a public Swift Package. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before contributing.

## License

Yashima is available under the MIT license. See [LICENSE](LICENSE).
