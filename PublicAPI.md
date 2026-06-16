# Public API Draft

This file tracks the intended public surface before implementation. Keep it small and review it before adding new symbols.

## Core Types

- `YCache`
- `YCache.Typed<C: CacheCodec>`
- `YCache.Configuration`
- `YCache.Options`
- `YCache.Resolved<Value>`
- `YCache.Source`
- `YCache.Metadata`
- `YCache.StorageUsage`
- `YCache.Error`
- `CacheKey`
- `CacheKeyComponent`
- `CacheCodec`
- `CacheLookupPolicy`
- `CacheWritePolicy`
- `CacheReadFailurePolicy`
- `CacheWriteFailurePolicy`
- `CacheCost`

`Y` is reserved for the root type `YCache`. Do not introduce `YKey`, `YCodec`, or other prefixed vocabulary types.

## Standard Codecs

- `DataCodec`
- `CodableCodec<Value>`
- `CodableCodec<Value>.Format`
- `ImageCodec`
- `ImageCodec.Format`
- `ImageCodec.Error`

`ImageCodec` is available on Apple platforms with image frameworks. The `jpeg` and `png` convenience APIs accept and return `UIImage` when UIKit is available and `NSImage` when AppKit is available. Direct codec usage stores platform images through `ImageCodec.Value`, a small Sendable wrapper around the platform image.

## Standard Convenience

These APIs are intended to be the first touch points in README examples.

- `jpeg(for:_:)`
- `jpeg(for:quality:_:)`
- `optionalJPEG(for:quality:_:)`
- `png(for:_:)`
- `optionalPNG(for:_:)`
- `data(for:_:)`
- `codable(for:_:)`
- `codable(for:format:_:)`

Do not add per-type versions of every cross-cutting operation in v0.1.

Default standard identities:

- `DataCodec().identifier == "data-v1"`
- `CodableCodec<Value>(format: .json).identifier == "codable-json-v1:<module-qualified-type>"`
- `CodableCodec<Value>(format: .propertyList).identifier == "codable-property-list-binary-v1:<module-qualified-type>"`
- `ImageCodec.png.identifier == "image-png-v1"`
- `ImageCodec.jpeg(quality: 0.85).identifier == "image-jpeg-q85-v1"`

`jpeg(for:)` is a thin alias for `jpeg(for:quality:)` with quality `0.85`.

## Codec API

- `value(for:codec:options:_:)`
- `resolve(for:codec:options:_:)`
- `valueIfCached(for:codec:)`
- `refresh(for:codec:options:_:)`
- `optionalValue(for:codec:options:_:)`
- `peek(for:codec:) async throws`
- `metadata(for:codec:) async throws`
- `contains(for:codec:) async throws`
- `putInMemory(_:for:codec:) async throws`
- `store(_:for:codec:options:) async throws`
- `remove(for:codec:) async throws -> Bool`
- `removeAll() async throws`
- `removeAll(in:) async throws`
- `storageUsage() async throws -> YCache.StorageUsage`
- `trimStorageIfNeeded() async throws -> YCache.StorageUsage`
- `using(_:)`

`metadata(for:codec:)` and `contains(for:codec:)` do not decode the stored
payload. They validate the cache identity and the presence of the stored data
file, but they do not guarantee that a later decode or content digest check will
succeed. These lookup APIs may clean up invalid metadata or missing data files.

`removeAll(in:)` removes entries whose `CacheKey.namespace` matches the supplied
namespace. More expressive tag or predicate invalidation is intentionally not in
the initial public surface.

`YCache.Configuration.storageMaximumByteCount` enables storage trimming. When the
limit is set, storage writes trim entries by least recent storage access. Storage
hits update `lastAccessedAt`. `storageUsage()` and storage trimming are based on
stored metadata and may clean up invalid metadata, missing data files, and
orphaned data files. They do not read and hash every stored payload; content
digest mismatches are detected on read.

`YCache.Options` includes:

- `readFailurePolicy`, default `.treatAsMiss`
- `writeFailurePolicy`, default `.throwError`

`.treatAsMiss` is intended for disposable generated artifacts. Use `.throwError`
when a caller needs strict cache corruption or decode failure reporting. It is
limited to recoverable cache read failures such as corrupt cache metadata,
missing cache data, content digest mismatches, and decode failures.

`CacheWriteFailurePolicy.bestEffort` treats storage write failure as a
memory-only fallback when memory writes are enabled. Generator failures, encode
failures, and read failures are not part of this policy.

## Typed Facade

`YCache.Typed<C>` may expose the full typed operation set without adding per-type root methods.

- `value(for:options:_:)`
- `resolve(for:options:_:)`
- `valueIfCached(for:)`
- `refresh(for:options:_:)`
- `optionalValue(for:options:_:)`
- `peek(for:) async throws`
- `metadata(for:) async throws`
- `contains(for:) async throws`
- `putInMemory(_:for:) async throws`
- `store(_:for:options:) async throws`
- `remove(for:) async throws -> Bool`

The initial implementation keeps memory access behind actors, so `peek` and `putInMemory` are async in v0.1. A future synchronous memory-only helper should be added only if the memory layer is explicitly designed for that guarantee.

## Initially Excluded

- `image(for:)` with an implicit image format
- `imageIfCached`
- Implicit `optionalImage`
- `refreshImage`
- `peekImage`
- `putImageInMemory`
- `image(for:format:)`
- Sync get-or-generate
- Sync disk read
- Sync disk write completion guarantee
- Sync memory-only `peek`
- Sync memory-only `putInMemory`
- Public stale/freshness policy
- Public tag invalidation
- Public predicate invalidation
- URL loading
- UI components
