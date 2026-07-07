<p align="right">
  <strong>English</strong> | <a href="Recipes.ja.md">日本語</a>
</p>

# Recipes

These recipes show practical Yashima patterns for Swift apps that repeatedly
generate local artifacts.

The examples are synthetic.
They are shaped by real app workloads, but they avoid app-specific models,
private paths, logs, and user data.

## Pick a Recipe

| Workload | Codec | Options | Key inputs to include |
|---|---|---|---|
| Scrolling thumbnails and previews | `ImageCodec.jpeg` or `ImageCodec.png` | `.uiLifecycle` | source identity, source revision, size, scale, crop, renderer version |
| Small derived metadata | `CodableCodec` | `.default` | source identity, source revision, metadata schema or reader version |
| Rendered document payloads | `CompressedDataCodec` or a custom compressed codec | `.default` with measured cost | document identity, content revision, renderer version, locale, appearance |
| Search artifacts | custom codec or `CodableCodec` | cache-only reads plus explicit stores | candidate identity, source revision, normalizer version, artifact schema |
| Filter and variant previews | `ImageCodec.jpeg` or `ImageCodec.png` | `.uiLifecycle` | source identity, base transform, candidate transform, output size, renderer version |

## Shared Cache Owner

Most apps should start with one long-lived `YCache` for generated artifacts.
Use namespaces to separate artifact kinds inside that cache.

```swift
import Foundation
import Yashima

enum AppArtifactCache {
    static let shared = YCache(
        storageDirectory: FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("GeneratedArtifacts", isDirectory: true),
        memoryMaximumCost: 96 * 1024 * 1024,
        memoryMaximumEntryCount: nil,
        storageMaximumByteCount: 512 * 1024 * 1024
    )
}
```

Create a separate `YCache` only when the storage directory, quota, lifecycle, or
security boundary is intentionally different.
Do not create several cache instances that point at the same directory just
because they use different namespaces.

## Scrolling Thumbnails

Use this pattern for `List`, `LazyVGrid`, or collection-style UI where cells
request local thumbnails and disappear quickly.

```swift
import UIKit
import Yashima

func thumbnail(
    assetID: String,
    sourceRevision: String,
    pointSize: CGSize,
    scale: CGFloat
) async throws -> UIImage? {
    let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

    let key = CacheKey(namespace: "media-thumbnails", identity: assetID)
        .variant("sourceRevision", sourceRevision)
        .variant("pixels", "\(Int(pixelSize.width))x\(Int(pixelSize.height))")
        .variant("scale", scale)
        .variant("crop", "center-square")
        .version("renderer", 1)

    return try await AppArtifactCache.shared.optionalJPEG(
        for: key,
        quality: 0.85,
        options: .uiLifecycle
    ) {
        try Task.checkCancellation()
        return try await renderThumbnail(assetID: assetID, pointSize: pointSize, scale: scale)
    }
}
```

In SwiftUI, bind the request to the view lifecycle with `.task(id:)`, then check
that the cell still represents the same identity before assigning the result.

```swift
.task(id: assetID) {
    let requestID = assetID
    let image = try? await thumbnail(
        assetID: assetID,
        sourceRevision: sourceRevision,
        pointSize: CGSize(width: 96, height: 96),
        scale: displayScale
    )

    guard !Task.isCancelled, requestID == assetID else { return }
    thumbnailImage = image
}
```

For this kind of work, `.uiLifecycle` is usually the right default.
If every visible caller disappears, Yashima can cancel the shared producer
instead of finishing work for a cell that is no longer visible.

## Video Duration or Small Metadata

Small generated metadata can use `CodableCodec`.
Keep it separate from image namespaces so it can be inspected, cleared, or
tuned independently.

```swift
import AVFoundation
import Yashima

func videoDuration(
    videoID: String,
    fileSize: Int,
    modifiedAt: Date
) async throws -> TimeInterval {
    let key = CacheKey(namespace: "video-durations", identity: videoID)
        .variant("fileSize", fileSize)
        .variant("modifiedAt", Int64(modifiedAt.timeIntervalSince1970 * 1_000_000))
        .version("reader", 1)

    return try await AppArtifactCache.shared.codable(for: key) {
        try await loadDurationFromAsset(videoID: videoID)
    }
}
```

This pattern fits values derived from local media or app files, such as
durations, dimensions, page counts, extracted titles, or lightweight manifests.
It does not make those values authoritative.
If the value must survive cache clearing, store it in the app's persistence
layer instead.

## Rendered Document Payload

Rendered documents are often larger than a thumbnail and cheaper to transmit as
bytes.
For HTML, JSON, manifests, or other text-like output, start with
`CompressedDataCodec`.

```swift
import Foundation
import Yashima

func renderedHTML(
    documentID: String,
    contentRevision: String,
    appearance: String,
    localeIdentifier: String
) async throws -> Data {
    let key = CacheKey(namespace: "rendered-documents", identity: documentID)
        .variant("contentRevision", contentRevision)
        .variant("appearance", appearance)
        .variant("locale", localeIdentifier)
        .version("renderer", 4)

    return try await AppArtifactCache.shared.value(
        for: key,
        codec: CompressedDataCodec(),
        options: YCache.Options(
            cost: .bytes(256 * 1024),
            writeFailurePolicy: .bestEffort
        )
    ) {
        let html = try await renderDocumentHTML(documentID: documentID)
        return Data(html.utf8)
    }
}
```

If the artifact contains several structured pieces, define a custom codec with a
versioned identifier.
The codec identifier becomes part of the stored-entry identity, so changing the
format does not collide with older bytes.

```swift
import Foundation
import Yashima

struct FirstPaintArtifact: Codable, Sendable {
    var html: Data
    var title: String
    var headings: [String]
}

struct FirstPaintArtifactCodec: CacheCodec {
    let identifier = "first-paint-artifact-plist-lzfse-v1"

    func encode(_ value: FirstPaintArtifact) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let propertyList = try encoder.encode(value)
        return try (propertyList as NSData).compressed(using: .lzfse) as Data
    }

    func decode(_ data: Data) throws -> FirstPaintArtifact {
        let propertyList = try (data as NSData).decompressed(using: .lzfse) as Data
        return try PropertyListDecoder().decode(FirstPaintArtifact.self, from: propertyList)
    }
}
```

Use this for first-paint payloads, rendered previews, normalized document
summaries, or other derived document artifacts.
Do not store the user's only document copy in Yashima.

## Search Artifacts

Search is usually not one cache entry for the entire index.
A safer pattern is to cache derived artifacts per candidate document, then let
the search engine decide how to combine current candidates.

```swift
import Yashima

struct SearchArtifact: Codable, Sendable {
    var normalizedLines: [String]
    var tokenCount: Int
    static let schemaVersion = 1
}

struct SearchCandidate: Sendable {
    var documentID: String
    var sourceRevision: String
}

func searchArtifactKey(
    candidate: SearchCandidate,
    normalizerVersion: String
) -> CacheKey {
    CacheKey(namespace: "search-artifacts", identity: candidate.documentID)
        .variant("sourceRevision", candidate.sourceRevision)
        .version("normalizer", normalizerVersion)
        .version("schema", SearchArtifact.schemaVersion)
}
```

Read with `cacheOnly` when the caller only wants to know whether a prepared
artifact already exists.
Store explicitly after the search pipeline has produced a valid artifact.

```swift
let lookupOptions = YCache.Options(
    lookupPolicy: .cacheOnly,
    readFailurePolicy: .throwError,
    writeFailurePolicy: .throwError,
    singleFlightPolicy: .disabled
)

let storeOptions = YCache.Options(
    cost: .bytes(estimatedMemoryCost),
    writeFailurePolicy: .throwError,
    singleFlightPolicy: .disabled
)

let key = searchArtifactKey(candidate: candidate, normalizerVersion: "v3")
let codec = CodableCodec<SearchArtifact>(format: .propertyList)

let cached = try? await AppArtifactCache.shared.value(
    for: key,
    codec: codec,
    options: lookupOptions
) {
    throw YCache.Error.cacheMiss
}

if cached == nil {
    let artifact = try await buildSearchArtifact(candidate)
    try await AppArtifactCache.shared.store(
        artifact,
        for: key,
        codec: codec,
        options: storeOptions
    )
}
```

This keeps Yashima in the disposable-artifact role.
The current document list, permissions, query state, and authoritative document
contents still belong to the app.

## Filter or Variant Previews

When a UI lets users preview several image variants, encode both the base source
and the candidate transform in the key.

```swift
func filterPreviewKey(
    imageID: String,
    sourceDigest: String,
    pixelSize: String,
    baseFilter: String?,
    candidateFilter: String
) -> CacheKey {
    CacheKey(namespace: "filter-previews", identity: imageID)
        .variant("sourceDigest", sourceDigest)
        .variant("pixels", pixelSize)
        .variant("baseFilter", baseFilter ?? "none")
        .variant("candidateFilter", candidateFilter)
        .variant("resize", "aspect-fill")
        .version("filterRenderer", 1)
}
```

This is useful when the same source image appears in a grid, a detail view, and
temporary preview controls.
Keep separate namespaces for thumbnails, full-size derived images, and filter
previews if the app needs different clearing or tuning behavior.

## Operational Checklist

- Include every input that changes the generated bytes in `CacheKey`.
- Put schema, renderer, normalizer, and reader changes in `version(_:_:)`.
- Keep absolute paths, raw file URLs, and private user content out of public
  logs and examples.
- Prefer `.uiLifecycle` for scrolling or tile-based UI work.
- Keep default `.share` behavior for background work, detail screens, exports,
  and generation that remains valuable after the first caller disappears.
- Use `CompressedDataCodec` for large text-like `Data`, not for JPEG, PNG, or
  video data unless measurement shows a benefit.
- Treat `nil` as "no artifact now", not as persisted negative cache state.
- Use `removeAll(in:)` for clearable namespaces such as thumbnails, previews, or
  search artifacts.
- Store authoritative data somewhere else.
