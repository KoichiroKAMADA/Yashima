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
- `YCache.Error`
- `CacheKey`
- `CacheKeyComponent`
- `CacheCodec`
- `CacheLookupPolicy`
- `CacheWritePolicy`
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
- `png(for:_:)`
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
- `putInMemory(_:for:codec:) async throws`
- `store(_:for:codec:options:) async throws`
- `using(_:)`

## Typed Facade

`YCache.Typed<C>` may expose the full typed operation set without adding per-type root methods.

- `value(for:options:_:)`
- `resolve(for:options:_:)`
- `valueIfCached(for:)`
- `refresh(for:options:_:)`
- `optionalValue(for:options:_:)`
- `peek(for:) async throws`
- `putInMemory(_:for:) async throws`
- `store(_:for:options:) async throws`

The initial implementation keeps memory access behind actors, so `peek` and `putInMemory` are async in v0.1. A future synchronous memory-only helper should be added only if the memory layer is explicitly designed for that guarantee.

## Initially Excluded

- `image(for:)` with an implicit image format
- `imageIfCached`
- `refreshImage`
- `optionalImage`
- `peekImage`
- `putImageInMemory`
- `image(for:format:)`
- Sync get-or-generate
- Sync disk read
- Sync disk write completion guarantee
- Sync memory-only `peek`
- Sync memory-only `putInMemory`
- Public corruption policy override
- Public stale/freshness policy
- Public tag invalidation
- URL loading
- UI components
