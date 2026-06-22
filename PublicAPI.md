# Public API

This file tracks the implemented public surface for the first public release
line. Keep it small and review it before adding new symbols.

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
- `CacheSingleFlightPolicy`
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
- `jpeg(for:quality:options:_:)`
- `optionalJPEG(for:quality:_:)`
- `optionalJPEG(for:quality:options:_:)`
- `png(for:_:)`
- `png(for:options:_:)`
- `optionalPNG(for:_:)`
- `optionalPNG(for:options:_:)`
- `data(for:_:)`
- `data(for:options:_:)`
- `codable(for:_:)`
- `codable(for:format:_:)`
- `codable(for:format:options:_:)`

Do not add per-type versions of every cross-cutting operation unless the added
convenience removes real friction from common usage.

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

`YCache.Configuration` exposes default budget constants:

- `defaultMemoryMaximumCost == 64 * 1024 * 1024`
- `defaultMemoryMaximumEntryCount == nil`
- `defaultStorageMaximumByteCount == 128 * 1024 * 1024`

The convenience initializer and `Configuration(storageDirectory:)` use those
finite memory and storage budgets when the parameters are omitted. Passing
`memoryMaximumCost: nil` or `storageMaximumByteCount: nil` explicitly keeps that
layer unbounded. `memoryMaximumEntryCount` is optional and has no default limit.

`YCache.Configuration.storageMaximumByteCount` enables storage trimming. When the
limit is set, storage writes trim entries by least recent storage access. Storage
hits update `lastAccessedAt`. `storageUsage()` and storage trimming are based on
stored metadata and may clean up invalid metadata, missing data files, and
orphaned data files. They do not read and hash every stored payload; content
digest mismatches are detected on read.

`YCache.Options` includes:

- `cost`, optional explicit cost override
- `lookupPolicy`, default `.normal`
- `writePolicy`, default `.memoryAndStorage`
- `readFailurePolicy`, default `.treatAsMiss`
- `writeFailurePolicy`, default `.throwError`
- `singleFlightPolicy`, default `.share`

`YCache.Options.default` is the default option set.

`YCache.Options.uiLifecycle` is the recommended preset for SwiftUI `List`,
`LazyVGrid`, `.task(id:)`, scrolling cells, and other caller-lifetime-bound
artifact generation. It currently means:

- `writeFailurePolicy == .bestEffort`
- `singleFlightPolicy == .cancelWhenNoWaiters`

Because it uses `.bestEffort`, storage write failures fall back to memory-only
results when memory writes are enabled. Generator failures, encode failures, and
read failures still keep their normal error behavior.

Keep `.default` / `.share` as the normal choice for background work, detail
screens, exports, and generation where completing the producer still has value
after the original caller disappears.

When `cost` is omitted, `DataCodec` and `CodableCodec` use encoded byte count as
their memory cost. `ImageCodec` estimates decoded bitmap memory instead of using
the compressed PNG or JPEG byte count. When `cost` is provided, that explicit
cost wins.

`.treatAsMiss` is intended for disposable generated artifacts. Use `.throwError`
when a caller needs strict cache corruption or decode failure reporting. It is
limited to recoverable cache read failures such as corrupt cache metadata,
missing cache data, content digest mismatches, and decode failures.

`CacheWriteFailurePolicy.bestEffort` treats storage write failure as a
memory-only fallback when memory writes are enabled. Generator failures, encode
failures, and read failures are not part of this policy.

`CacheSingleFlightPolicy` controls how concurrent misses for the same key, codec,
and sharing policy share generation work:

- `.share` is the default. Waiters share one producer. Cancelling one waiter
  does not cancel the producer while other waiters or future joiners may still
  use it.
- `.cancelWhenNoWaiters` is intended for UI lifecycle work. Cancelling one
  waiter only cancels that waiter, but when all waiters are gone the producer is
  cancelled, the in-flight entry is removed, and cancelled results are not
  stored.
- `.disabled` skips in-flight sharing so each caller performs its own lookup and
  generation path.

Generator closures should be cancellation-aware when using
`.cancelWhenNoWaiters`. Yashima can cancel the producer task and avoid storing a
cancelled result, but long-running renderers still need to check cancellation or
cancel their underlying work.

`optionalValue(for:codec:options:_:)` uses the same lookup, single-flight, and
producer cancellation path as `value(for:codec:options:_:)`.

- If a cached value exists, it returns that value and does not run the generator.
- If the generator returns a value, Yashima stores it according to the write
  policy and returns it to the waiters.
- If the generator returns `nil`, Yashima returns `nil` to current waiters and
  does not store a negative cache entry.
- If the generator throws or task cancellation wins, Yashima does not store an
  entry.
- With `.cancelWhenNoWaiters`, when all waiters are cancelled, the producer task
  is cancelled and no cancelled result is stored.
- With `.disabled`, each caller runs its own miss-generation path.

`optionalJPEG` and `optionalPNG` are thin wrappers over that optional-value
semantics.

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

The current implementation keeps memory access behind actors, so `peek` and
`putInMemory` are async. A future synchronous memory-only helper should be added
only if the memory layer is explicitly designed for that guarantee.

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
- Failure markers or negative-cache entries
- AVFoundation thumbnail APIs
- PhotoKit thumbnail APIs
- URL loading
- UI components
