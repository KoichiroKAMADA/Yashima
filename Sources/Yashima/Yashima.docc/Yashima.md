# Yashima

Yashima is a Swift Concurrency-first local artifact cache for generated app
artifacts that are expensive to recreate but safe to regenerate.

Use Yashima when your app repeatedly renders local thumbnails, previews, map
snapshots, charts, summaries, waveforms, rendered document payloads, or other
deterministic generated values. It gives that workflow a small async API, typed
codecs, memory and file-backed storage, quota-based trimming, and single-flight
generation.

Yashima is not a URL image loader and not a database. Remote image downloading,
authoritative app data, originals, documents, recordings, and user-created files
belong in tools that own those problems directly.

## Overview

The common path is a get-or-generate call:

```swift
let cache = YCache(storageDirectory: cacheDirectory)

let thumbnail = try await cache.jpeg(for: key) {
    try await renderThumbnail()
}
```

The generated value is stored through a codec. The effective stored-entry
identity includes both the canonical ``CacheKey`` and the
``CacheCodec/identifier`` so the same logical key can hold distinct artifacts,
such as JPEG and PNG versions.

## Topics

### Essentials

- ``YCache``
- ``YCache/Options``
- ``YCache/Resolved``
- ``YCache/Source``
- ``YCache/Metadata``
- ``YCache/StorageUsage``

### Cache Keys

- ``CacheKey``
- ``CacheKeyComponent``
- <doc:DesigningCacheKeys>

### Codecs

- ``CacheCodec``
- ``DataCodec``
- ``CompressedDataCodec``
- ``CodableCodec``
- ``ImageCodec``
- <doc:ChoosingACodec>

### Policies and Lifecycle

- ``CacheLookupPolicy``
- ``CacheWritePolicy``
- ``CacheReadFailurePolicy``
- ``CacheWriteFailurePolicy``
- ``CacheSingleFlightPolicy``
- ``CacheCost``
- <doc:CancellationAndUILifecycle>
