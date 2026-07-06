<p align="right">
  <strong>English</strong> | <a href="README.ja.md">日本語</a>
</p>

# Yashima

<p align="center">
  <a href="https://github.com/KoichiroKAMADA/Yashima/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/KoichiroKAMADA/Yashima/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/KoichiroKAMADA/Yashima/releases"><img alt="Release" src="https://img.shields.io/github/v/release/KoichiroKAMADA/Yashima?sort=semver"></a>
  <img alt="Swift 6.1+" src="https://img.shields.io/badge/Swift-6.1%2B-F05138?logo=swift&logoColor=white">
  <img alt="iOS 16+ | macOS 13+" src="https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/KoichiroKAMADA/Yashima"></a>
</p>

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
- Typed codecs for `Data`, LZFSE-compressed `Data`, `Codable`, PNG, and JPEG
  artifacts.
- Cache identity based on both `CacheKey` and `CacheCodec.identifier`.
- Single-flight generation so concurrent requests for the same artifact share
  work.
- Cancellation-aware single-flight for UI-generated artifacts whose callers can
  disappear while work is still running.
- Disposable-cache failure semantics: corrupt stored artifacts can be treated as
  misses and regenerated.

## When Not to Use Yashima

Yashima is deliberately narrow. Use it for disposable local artifacts that an app
can regenerate. Choose a different tool when the data has different ownership:

- For downloading, decoding, and caching remote images, use an image pipeline
  such as [Nuke](https://github.com/kean/Nuke) or
  [Kingfisher](https://github.com/onevcat/Kingfisher).
- For structured app data that must be preserved, use a database or persistence
  layer such as SwiftData, Core Data, SQLite, or GRDB.
- For user-created files, originals, documents, recordings, or anything that
  cannot safely disappear, do not store the only copy in Yashima.
- For in-memory-only object reuse, `NSCache` may be the simpler choice.
- For negative caching, such as remembering that no value exists, model that
  state in your app. Yashima does not persist `nil` generator results.

See [Comparison](Documentation/Comparison.md) for a fuller, respectful comparison
with adjacent cache and image-loading libraries.

## Installation

Yashima is distributed as a Swift Package. In Xcode, add this repository from
File > Add Package Dependencies.

For `Package.swift`, use the `0.5.x` release line while Yashima is pre-1.0:

```swift
dependencies: [
    .package(
        url: "https://github.com/KoichiroKAMADA/Yashima.git",
        .upToNextMinor(from: "0.5.0")
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

## Docs and Guides

- [PublicAPI.md](PublicAPI.md): public API inventory and design intent.
- [DocC catalog](Sources/Yashima/Yashima.docc): documentation source for hosted
  API documentation after Swift Package Index indexing.
- [Comparison](Documentation/Comparison.md): when to choose Yashima and when to
  choose adjacent tools.
- [CHANGELOG.md](CHANGELOG.md): release history.
- [Benchmarks](Benchmarks): reproducible local measurement harness.

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
6. A minimal Swift Package Manager integration plan using version 0.5.0.

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

## Compressed Data Artifacts

For large text-like generated data such as rendered HTML, JSON, manifests, or
summaries, opt into LZFSE compression with `CompressedDataCodec`:

```swift
let documents = cache.using(CompressedDataCodec())

let htmlData = try await documents.value(for: key) {
    Data(renderedHTML.utf8)
}
```

Compression is explicit. `DataCodec` remains uncompressed, and compressed
entries use a distinct codec identity. Avoid using `CompressedDataCodec` for
already-compressed formats such as JPEG, PNG, or video data unless measurement
shows a benefit.

## Optional Artifacts

Some generators legitimately have no artifact to return. For example, a video
thumbnail request may fail because the source file disappeared, or a photo
thumbnail request may decide that no displayable image is available.

Use `optionalValue`, `optionalJPEG`, or `optionalPNG` for those cases:

```swift
let thumbnail = try await cache.optionalJPEG(
    for: key,
    options: .uiLifecycle
) {
    try await renderThumbnailIfAvailable()
}
```

`nil` means "no artifact", not "a negative cache entry". Yashima does not store
`nil`, `CancellationError`, or thrown failures. If several callers miss the same
key at the same time, optional generation still participates in single-flight:
one producer runs, successful values are stored, and `nil` is shared with the
current waiters without being persisted.

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

When code outside Yashima needs a key-derived string, use
`key.stableIdentifier`. It is a stable, opaque identifier for the `CacheKey`
alone, suitable for auxiliary file names, log labels, or process-to-process
deduplication. Do not treat it as a stored cache entry identifier: a storage
entry is identified by the `CacheKey` and the `CacheCodec.identifier` together.

The rule of thumb is simple: if two generations can produce different bytes,
their `CacheKey` should be different. If the key is right, cached values may be
evicted and regenerated, but they should never be the wrong artifact for the
request.

For video thumbnails, keep absolute paths and raw file URLs out of keys and
logs. Prefer a stable app-level identity plus the inputs that can change the
thumbnail:

```swift
let key = CacheKey(namespace: "video-thumbnails", identity: videoIdentity)
    .variant("fileSize", fileSize)
    .variant("createdAt", createdAt.timeIntervalSince1970)
    .variant("modifiedAt", modifiedAt.timeIntervalSince1970)
    .variant("second", thumbnailSecond)
    .variant("pixels", "\(pixelWidth)x\(pixelHeight)")
    .variant("scale", scale)
    .variant("crop", "center-square")
    .version("renderer", 1)
```

Use the asset timeline position you render, such as `thumbnailSecond`; do not
include wall-clock request or generation time unless that time truly changes the
artifact bytes.

## Share One Cache Instance

For a typical iOS app, prefer one long-lived `YCache` instance for the app's
generated artifacts. Keep it in a small shared owner such as an app cache
service, dependency container, actor, or `AppArtifactCache.shared`.

Use `CacheKey.namespace` to separate artifact kinds inside that shared cache:

```swift
enum AppArtifactCache {
    static let shared = YCache(storageDirectory: cacheDirectory)
}

let thumbnailKey = CacheKey(namespace: "video-thumbnails", identity: videoID)
let durationKey = CacheKey(namespace: "video-durations", identity: videoID)

let thumbnail = try await AppArtifactCache.shared.jpeg(for: thumbnailKey) {
    try await renderThumbnail()
}

let duration: Double = try await AppArtifactCache.shared.codable(for: durationKey) {
    try await loadDuration()
}
```

Namespaces are logical partitions within a cache; they are not a reason to
create one `YCache` instance per namespace. Create multiple `YCache` instances
only when you intentionally need different storage directories, budgets,
lifecycle rules, security boundaries, app-extension boundaries, or isolated
test/preview stores. If two cache instances would point at the same
`storageDirectory`, prefer one shared instance instead. When in doubt, use one
shared `YCache` and separate artifact kinds with namespaces.

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
chart snapshots, use the `uiLifecycle` preset so work stops when nothing on
screen is still waiting for it:

```swift
let snapshot = try await cache.png(for: key, options: .uiLifecycle) {
    try Task.checkCancellation()
    return try await renderSnapshot()
}
```

`YCache.Options.uiLifecycle` combines
`singleFlightPolicy: .cancelWhenNoWaiters` with
`writeFailurePolicy: .bestEffort`. Use the default `.share` behavior for
background work, detail screens, exports, or any generation where completing the
producer still has value after the original caller disappears.
Because it uses `.bestEffort`, a storage write failure silently degrades to a
memory-only result when memory writes are enabled; generator failures still
throw.

Yashima separates waiter cancellation from producer cancellation. If one waiter
is cancelled while other waiters remain, the producer keeps running for the
remaining callers. If every waiter is cancelled, Yashima cancels the producer,
removes the in-flight entry, and does not store a cancelled generation result.
The generator still owns its side of the contract: long-running renderers should
check cancellation and cancel underlying work such as snapshotters when their
own task is cancelled.

Use `.disabled` only when each caller should run an independent generation even
for the same key.

## iOS Recipes

Yashima core does not import AVFoundation, PhotoKit, SwiftUI, or app-specific
thumbnail generators. Those producers belong in your app or in a separate
adapter package. Yashima's job is to cache the generated `Data`, `Codable`, PNG,
or JPEG values with predictable key, single-flight, and cancellation semantics.

For a SwiftUI cell or grid item, bind the caller task to the view lifecycle with
`.task(id:)`, use `.uiLifecycle`, and check identity before assigning the image
back to state:

```swift
.task(id: videoID) {
    let requestID = videoID
    let image = try? await cache.optionalJPEG(for: key, options: .uiLifecycle) {
        try await renderVideoThumbnail()
    }

    guard !Task.isCancelled, requestID == videoID else { return }
    thumbnailImage = image
}
```

Avoid starting unstructured tasks from `.onAppear { Task { ... } }` for
scrolling cells. They are easier to accidentally outlive the view that requested
the artifact.

For AVFoundation thumbnails, prefer the async `AVAssetImageGenerator.image(at:)`
API on supported OS versions and connect task cancellation to the producer:

```swift
let generator = AVAssetImageGenerator(asset: asset)
let time = CMTime(seconds: thumbnailSecond, preferredTimescale: 600)

let cgImage = try await withTaskCancellationHandler {
    let result = try await generator.image(at: time)
    return result.image
} onCancel: {
    generator.cancelAllCGImageGeneration()
}
```

If your app still uses `copyCGImage(at:actualTime:)`, remember that it is a
synchronous API. Checking task cancellation before and after the call is useful,
but it cannot guarantee immediate interruption while the synchronous generation
is already running.

For PhotoKit thumbnails, keep the key tied to the `PHAsset` identity and the
requested representation, not to a transient `UIImage`:

```swift
let key = CacheKey(namespace: "photo-thumbnails", identity: asset.localIdentifier)
    .variant("pixels", "\(pixelWidth)x\(pixelHeight)")
    .variant("contentMode", "aspectFill")
    .variant("deliveryMode", "highQuality")
    .version("renderer", 1)
```

`PHImageManager` may deliver more than one result depending on request options.
Cache the final representation that matches your key, or include the quality
level in the key. If the surrounding task is cancelled, cancel the Photos
request by keeping the `PHImageRequestID` returned from `requestImage` and
passing it to `cancelImageRequest(_:)`. Avoid synchronous PhotoKit requests for
UI lifecycle work because they cannot be cancelled once started.

For small derived values such as video duration, use a separate namespace and a
`Codable` value:

```swift
let key = CacheKey(namespace: "video-durations", identity: videoIdentity)
    .variant("durationSource", "asset-metadata")
    .version("schema", 1)

let duration: Double = try await cache.codable(for: key) {
    try await loadDuration()
}
```

Keep image thumbnails and small metadata in different namespaces, such as
`video-thumbnails`, `photo-thumbnails`, `video-durations`, or `video-metadata`,
so cache clearing and future budget tuning stay understandable. These namespaces
normally live inside the same shared `YCache` instance.

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
`CacheKey.stableIdentifier` exposes only the key portion of that identity for
callers that need a stable string outside the cache.

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

## Benchmark Harness

Yashima includes a small local benchmark harness in [`Benchmarks`](Benchmarks).
It is separate from the correctness stress runner and exists to make performance
claims reproducible before they are published:

```sh
swift run --package-path Benchmarks YashimaBenchmarks --iterations 200
```

Benchmark numbers depend heavily on hardware, OS version, storage state, and
payload shape. Treat local output as measurement input, not a universal claim.

## Used in App Store Apps

### Tracer - Easy Location Logger

<p align="center">
  <img src="Documentation/Assets/tracer-yashima-scroll.gif" alt="Tracer scrolling through map artifacts cached by Yashima" width="360">
</p>

Yashima powers generated-artifact caching in Tracer - Easy Location Logger, a
location-recording app on the App Store. Tracer generates many local artifacts
from recorded activity data: map snapshots, summaries, chart-ready data, and
list previews that appear while the user scrolls through logs and revisits past
records.

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

### Broader Production Use

Tracer - Easy Location Logger is the most detailed public case study, but it is
not the only production workload. The project author also uses Yashima across a
set of shipped independent App Store apps. These apps are part of why Yashima is
designed around real generated artifacts instead of demo-only image caching.

- [Mugen Clock](https://apps.apple.com/us/app/mugen-clock/id1064833509): an
  easy-to-read, highly customizable clock app with maintainer-reported
  2-million-plus downloads.
  Yashima caches background image thumbnails, color and blur filter previews,
  background video thumbnails, and duration metadata.
- [Mugen Sound](https://apps.apple.com/us/app/mugen-sound/id6748948810): an
  ambient sound app for focus, sleep, and noise masking. Yashima caches
  downsampled JPEG derivatives for sound artwork used in grids, playlists, and
  full-screen playback.
- [Mugen Player](https://apps.apple.com/us/app/mugen-player/id1265142965): a
  lightweight continuous media player. Yashima caches file, Photo Library, and
  bookmark thumbnails across browsing and playback surfaces.
- [Mugen Camera Non-Stop Cam](https://apps.apple.com/us/app/mugen-camera-non-stop-cam/id1142214008):
  a long-form video recording app built for reliable non-stop capture. Yashima
  caches video thumbnails and duration metadata for files recorded or managed in
  app storage.
- [Zero Camera](https://apps.apple.com/us/app/zero-camera/id1449814538): a fast
  video camera app that starts recording with minimal interaction. Yashima
  caches app-storage video thumbnails and duration metadata.
- [ZeroMD](https://apps.apple.com/us/app/zeromd/id6770927023): a lightweight
  Markdown viewer for quickly opening and reading `.md` and `.markdown` files
  on Mac. Yashima caches first-paint Markdown rendering artifacts so reopened
  documents can reuse generated HTML and navigation payloads.

Together, these apps exercise Yashima across image downsampling, filter-preview
generation, AVFoundation thumbnail extraction, small metadata caching, and
compressed document-rendering artifacts.

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

Yashima is a public Swift Package. See [CONTRIBUTING.md](CONTRIBUTING.md),
[SECURITY.md](SECURITY.md), [PublicAPI.md](PublicAPI.md), and
[CHANGELOG.md](CHANGELOG.md) before contributing.

## License

Yashima is available under the MIT license. See [LICENSE](LICENSE).
