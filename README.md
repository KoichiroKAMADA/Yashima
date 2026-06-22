<p align="right">
  <strong>English</strong> | <a href="README.ja.md">日本語</a>
</p>

# Yashima

<p align="center">
  <img src="Documentation/Assets/yashima-hero.jpg" alt="Yashima" width="840">
</p>

A Swift Concurrency-first cache engine for locally generated app artifacts.

Not an image downloader. Not a database.

Yashima is designed for expensive local results that are safe to regenerate:
thumbnails, previews, rendered charts, waveforms, summaries, and other derived
artifacts.

Use it when an app can recreate a value, but should not recreate it every time.
Yashima gives that workflow a small public API, typed codecs, memory + storage
caching, quota-based trimming, and Swift Concurrency-friendly single-flight
generation.

## Why Yashima

- One async get-or-generate call for the common path.
- L1 memory cache and L2 file-backed storage.
- Typed codecs for `Data`, `Codable`, PNG, and JPEG artifacts.
- Cache identity based on both `CacheKey` and `CacheCodec.identifier`.
- Single-flight generation so concurrent requests for the same artifact share
  work.
- Cancellation-aware single-flight for UI-generated artifacts whose callers can
  disappear while work is still running.
- Disposable-cache failure semantics: corrupt stored artifacts can be treated as
  misses and regenerated.

## Installation

Yashima is distributed as a Swift Package. In Xcode, add this repository from
File > Add Package Dependencies.

For `Package.swift`, use the `0.2.x` release line while Yashima is pre-1.0:

```swift
dependencies: [
    .package(
        url: "https://github.com/KoichiroKAMADA/Yashima.git",
        .upToNextMinor(from: "0.2.0")
    ),
]
```

Then add the `Yashima` product to the target that generates and reuses local
artifacts:

```swift
.target(
    name: "YourApp",
    dependencies: ["Yashima"]
)
```

## Ask Your Coding Agent If Yashima Fits

Yashima solves a narrow but high-impact problem: caching locally generated
artifacts that are expensive to recreate.

If your app repeatedly renders maps, thumbnails, charts, summaries, previews,
or other deterministic local data while scrolling, navigating, launching, or
revisiting screens, ask your AI coding agent to evaluate whether Yashima fits
your project.

Copy this prompt into your coding agent:

```text
Evaluate whether Yashima is a good fit for my Swift app.

Yashima:
https://github.com/KoichiroKAMADA/Yashima

First, read Yashima's README and public API. Then inspect my project for places
where the app repeatedly generates local artifacts such as map images,
thumbnails, charts, summaries, previews, encoded data, rendered documents, or
other deterministic results.

Look especially for work that happens during scrolling, screen transitions,
app launch, repeated navigation, or returning to previously viewed content.

Report:
1. Whether Yashima is a good fit for this project. If it is not a fit, say so.
2. Which specific code paths could benefit from it.
3. What cache keys and codecs should be used.
4. What should not be cached with Yashima.
5. The main risks: stale cache keys, privacy-sensitive data, disk usage, and cancellation behavior.
6. A minimal Swift Package Manager integration plan using version 0.2.0.

Do not add the dependency or edit code yet. First explain the expected benefit,
risks, and smallest safe integration plan.
```

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

The public API is intentionally small. Standard conveniences stay thin wrappers
over the codec-based core, so the simple path and the extensible path share the
same cache semantics.

`YCache` is the root type. The `Y` comes from Yashima; supporting vocabulary
stays descriptive with names like `CacheKey` and `CacheCodec`.

Image conveniences cache platform images as explicit PNG or JPEG data. On iOS
they accept and return `UIImage`; on macOS they accept and return `NSImage`. The
codec stores platform images through a small Sendable wrapper when used
directly. The default JPEG quality is `0.85`.

The codec-based core API is available first:

```swift
let cache = YCache(storageDirectory: cacheDirectory)
let reports = cache.using(ReportCodec())

let report = try await reports.value(for: key) {
    try await renderReport()
}

let immediate = try await reports.peek(for: key)
```

## Designing Cache Keys

The most important part of any cache is the key. Yashima can make storage,
memory, and concurrency predictable, but the app still needs to describe what
the generated artifact actually depends on.

For a small app, a key can be as simple as a stable string:

```swift
let key = CacheKey("thumbnail-\(photoID)", namespace: "thumbnails")
```

That stays pleasant while the identity is truly simple. Once a key starts
combining several interpolated fragments, it becomes hard to review what the
cache actually depends on. Yashima lets you move those pieces into named
components before the key turns into an opaque string: use `identity` for the
stable thing being cached, `variant(_:_:)` for inputs that change the rendered
result, and `version(_:_:)` when your renderer or schema changes:

```swift
let key = CacheKey(namespace: "summary-maps", identity: summaryID)
    .variant("kind", "route-map")
    .variant("size", "\(pixelWidth)x\(pixelHeight)")
    .variant("appearance", appearance)
    .variant("routeDigest", routeDigest)
    .variant("annotationDigest", annotationDigest)
    .variant("lineWidth", normalizedLineWidth)
    .version("renderer", 2)
```

A good key is not necessarily a long key, but it must be a complete key. Include
every input that can change the artifact: size, scale, appearance, locale,
renderer options, source-data revision, and any large input represented by a
stable digest. Do not use Swift `hashValue` or `Hasher` for persisted cache
identity; use a stable digest such as SHA-256 when you need to summarize a route,
chart dataset, or rendered document.

The rule of thumb is simple: if two generations can produce different bytes,
their `CacheKey` should be different. If the key is right, cached values may be
evicted and regenerated, but they should never be the wrong artifact for the
request.

## Default Cache Budgets

By default, `YCache` uses a 64 MiB memory budget and a 128 MiB storage budget.
Memory has no entry-count limit by default, so many small thumbnails can use the
available memory budget without being pushed out early by an arbitrary count.

These defaults are intentionally conservative. Yashima's storage hits are still
fast enough for many locally generated artifacts, so most apps should start with
the defaults and increase memory only after measuring a real workload. Keeping
memory modest helps the host app stay stable while the file-backed storage layer
continues to absorb larger generated results.

You can tune the budgets explicitly:

```swift
let cache = YCache(
    storageDirectory: cacheDirectory,
    memoryMaximumCost: 96 * 1024 * 1024,
    memoryMaximumEntryCount: 500,
    storageMaximumByteCount: 256 * 1024 * 1024
)
```

Pass `nil` explicitly for an unbounded layer:

```swift
let cache = YCache(
    storageDirectory: cacheDirectory,
    memoryMaximumCost: nil,
    storageMaximumByteCount: nil
)
```

## Cancellation and UI Lifecycle

The default single-flight behavior is conservative: concurrent requests for the
same key share one producer, and the producer continues even if one waiter is
cancelled. This keeps existing get-or-generate code predictable.

For UI lifecycle work such as scrolling cells, thumbnails, MapKit snapshots, or
chart snapshots, use `cancelWhenNoWaiters` so work stops when nothing on screen
is still waiting for it:

```swift
let options = YCache.Options(singleFlightPolicy: .cancelWhenNoWaiters)

let snapshot = try await cache.png(for: key, options: options) {
    try Task.checkCancellation()
    return try await renderSnapshot()
}
```

Yashima separates waiter cancellation from producer cancellation. If one waiter
is cancelled while other waiters remain, the producer keeps running for the
remaining callers. If every waiter is cancelled, Yashima cancels the producer,
removes the in-flight entry, and does not store a cancelled generation result.
The generator still owns its side of the contract: long-running renderers should
check cancellation and cancel underlying work such as snapshotters when their
own task is cancelled.

Use `.disabled` only when each caller should run an independent generation even
for the same key.

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
Yashima hashes the canonical `CacheKey` and codec identity internally.

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

## Stress Testing

Yashima includes an optional stress runner in [`StressTests`](StressTests). It is
separate from the regular `swift test` suite so ordinary validation stays fast,
while larger changes can be checked against heavier async and file-backed
workloads.

The stress runner uses deterministic synthetic data and validates correctness
under:

- single-flight bursts where many tasks request the same missing artifact;
- mixed `Data`, `Codable`, PNG, and JPEG artifact generation;
- lifecycle churn across refresh, lookup, metadata, removal, and namespace
  removal;
- storage quota pressure, exact-capacity replacement, and oversized-entry
  cleanup;
- default memory-limit pressure where older memory entries fall back to storage;
- recoverable corruption and cancellation-aware single-flight churn.

```sh
swift run --package-path StressTests YashimaStressRunner --profile smoke
```

For larger behavior changes, run the broader local profile:

```sh
swift run --package-path StressTests YashimaStressRunner --profile standard
```

The stress runner is not a benchmark claim. It is designed to catch correctness
regressions in the parts of a cache engine that are hardest to cover with small
unit tests: concurrency, disk-backed storage, trimming, corruption recovery, and
regeneration.

## Used in App Store Apps

### Tracer

<p align="center">
  <img src="Documentation/Assets/tracer-yashima-scroll.gif" alt="Tracer scrolling through map artifacts cached by Yashima" width="360">
</p>

Yashima powers generated-artifact caching in Tracer, a location-recording app on
the App Store. Tracer generates many local artifacts from recorded activity
data: map snapshots, summaries, chart-ready data, and list previews that appear
while the user scrolls through logs and revisits past records.

<p align="center">
  <a href="https://apps.apple.com/us/app/tracer-easy-location-logger/id1136146951">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="40">
  </a>
</p>

Those artifacts are expensive enough that repeatedly generating them on every
scroll, refresh, or screen transition would make the experience feel heavy.
Yashima turns cache hits into the normal path: generated results can be reused
from memory or storage, concurrent requests for the same artifact can share
work, and UI-driven generation can be cancelled when there are no remaining
waiters.

That production workload is the kind of problem Yashima is built for. It is not
a demo-only image cache; it is an App Store-grade cache engine for local results
that are safe to regenerate but too costly to recreate every time. The recording
above uses demo data from a Yashima-backed Tracer build.

### Share Your App

If you use Yashima in an app that is available on the App Store, please let the
project know. This section can feature apps built with Yashima as adoption
examples.

## Status

The cache identity, memory store, storage store, core engine, codec-based
`YCache` public API, standard codecs, lifecycle APIs, storage trimming, failure
policies, and README-first convenience helpers are implemented with Swift
Testing coverage. A separate stress runner exercises concurrency, cancellation,
and storage edge cases with synthetic workloads.

## Design Notes

- Swift Concurrency-first public API.
- L1 memory cache + L2 storage cache.
- Get-or-generate as the primary usage model.
- Data-first storage with typed codecs.
- `CacheKey` + codec identifier as the effective cache entry identity.
- Explicit invalidation, storage usage, and quota-based storage trimming.
- Cache semantics: values may disappear, but values returned by the cache must match their key, codec, and metadata.
- Swift Concurrency-first does not mean all disk I/O is non-blocking. Yashima
  keeps the public API async and actor-based while using Foundation file I/O
  under the hood.

## Requirements

- Swift 6.1 or later
- iOS 16+
- macOS 13+

## Contributing

Yashima is being prepared as a public Swift Package. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before contributing.

## License

Yashima is available under the MIT license. See [LICENSE](LICENSE).
