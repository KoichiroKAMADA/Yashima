import Foundation

/// A Swift Concurrency-first cache for locally generated artifacts.
public final class YCache: Sendable {
    /// The cache configuration used by this instance.
    public let configuration: Configuration

    private let engine: CacheCoreEngine

    /// Creates a cache from an explicit configuration.
    public init(configuration: Configuration) {
        self.configuration = configuration
        let memory = MemoryCacheStore(limits: configuration.memoryLimits)
        let storage = StorageCacheStore(
            rootDirectory: configuration.storageDirectory,
            maximumByteCount: configuration.storageMaximumByteCount
        )
        self.engine = CacheCoreEngine(memory: memory, storage: storage)
    }

    /// Creates a cache rooted at a storage directory with optional budgets.
    public convenience init(
        storageDirectory: URL,
        memoryMaximumCost: Int? = Configuration.defaultMemoryMaximumCost,
        memoryMaximumEntryCount: Int? = nil,
        storageMaximumByteCount: Int? = Configuration.defaultStorageMaximumByteCount
    ) {
        self.init(
            configuration: Configuration(
                storageDirectory: storageDirectory,
                memoryMaximumCost: memoryMaximumCost,
                memoryMaximumEntryCount: memoryMaximumEntryCount,
                storageMaximumByteCount: storageMaximumByteCount
            )
        )
    }

    /// Returns a typed facade for a codec.
    public func using<C: CacheCodec>(_ codec: C) -> Typed<C> {
        Typed(base: self, codec: codec)
    }

    /// Returns a cached value or generates, stores, and returns a new value.
    public func value<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> C.Value
    ) async throws -> C.Value {
        let resolved = try await resolve(
            for: key,
            codec: codec,
            options: options,
            generator
        )
        return resolved.value
    }

    /// Resolves a value and reports whether it came from memory, storage, or generation.
    public func resolve<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> C.Value
    ) async throws -> Resolved<C.Value> {
        try await translateCoreErrors {
            let resolved = try await engine.resolve(
                for: key,
                codec: codec,
                options: options.coreOptions,
                generator: generator
            )
            return Resolved(resolved)
        }
    }

    /// Returns a cached value if one is available.
    public func valueIfCached<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> C.Value? {
        try await resolvedIfCached(for: key, codec: codec, options: .default)?.value
    }

    /// Regenerates a value and updates the cache.
    public func refresh<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> C.Value
    ) async throws -> C.Value {
        var refreshOptions = options
        refreshOptions.lookupPolicy = .refresh
        return try await value(
            for: key,
            codec: codec,
            options: refreshOptions,
            generator
        )
    }

    /// Returns an optional generated value without storing `nil` results.
    public func optionalValue<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> C.Value?
    ) async throws -> C.Value? {
        do {
            return try await value(
                for: key,
                codec: codec,
                options: options
            ) {
                guard let value = try await generator() else {
                    throw OptionalGenerationReturnedNil()
                }
                return value
            }
        } catch is OptionalGenerationReturnedNil {
            return nil
        } catch Error.cacheMiss where options.lookupPolicy == .cacheOnly {
            return nil
        }
    }

    /// Returns a memory value without reading storage.
    public func peek<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> C.Value? {
        try await translateCoreErrors {
            let resolved = try await engine.peekMemory(for: key, codec: codec)
            return resolved?.value
        }
    }

    /// Returns cache metadata without decoding the stored payload.
    public func metadata<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Metadata? {
        try await translateCoreErrors {
            try await engine.metadata(for: key, codec: codec).map(Metadata.init)
        }
    }

    /// Returns whether memory or storage contains an entry for the key and codec.
    public func contains<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        try await translateCoreErrors {
            try await engine.contains(for: key, codec: codec)
        }
    }

    /// Stores a value in memory without writing to storage.
    public func putInMemory<C: CacheCodec>(
        _ value: C.Value,
        for key: CacheKey,
        codec: C,
        cost: CacheCost? = nil
    ) async throws {
        var options = Options(cost: cost)
        options.writePolicy = .memoryOnly
        _ = try await storeResolved(value, for: key, codec: codec, options: options)
    }

    /// Stores a value according to the supplied options.
    public func store<C: CacheCodec>(
        _ value: C.Value,
        for key: CacheKey,
        codec: C,
        options: Options = .default
    ) async throws {
        _ = try await storeResolved(value, for: key, codec: codec, options: options)
    }

    /// Removes the entry for a key and codec from memory and storage.
    @discardableResult
    public func remove<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        try await translateCoreErrors {
            try await engine.remove(for: key, codec: codec)
        }
    }

    /// Removes all Yashima-managed entries from this cache.
    public func removeAll() async throws {
        try await translateCoreErrors {
            try await engine.removeAll()
        }
    }

    /// Removes entries whose `CacheKey.namespace` matches the supplied namespace.
    public func removeAll(in namespace: String) async throws {
        try await translateCoreErrors {
            try await engine.removeAll(in: namespace)
        }
    }

    /// Returns storage usage for managed entries.
    public func storageUsage() async throws -> StorageUsage {
        try await translateCoreErrors {
            StorageUsage(try await engine.storageUsage())
        }
    }

    /// Trims storage to the configured byte budget and returns current usage.
    @discardableResult
    public func trimStorageIfNeeded() async throws -> StorageUsage {
        try await translateCoreErrors {
            StorageUsage(try await engine.trimStorageIfNeeded())
        }
    }
}

extension YCache {
    /// Configuration for memory and file-backed storage layers.
    public struct Configuration: Sendable, Equatable {
        /// The default memory budget in bytes.
        public static let defaultMemoryMaximumCost = 64 * 1024 * 1024
        /// The default memory entry-count limit.
        public static let defaultMemoryMaximumEntryCount: Int? = nil
        /// The default storage budget in bytes.
        public static let defaultStorageMaximumByteCount = 128 * 1024 * 1024

        /// The directory where Yashima stores file-backed entries.
        public var storageDirectory: URL
        /// The maximum in-memory cost, or `nil` for no cost limit.
        public var memoryMaximumCost: Int?
        /// The maximum number of in-memory entries, or `nil` for no count limit.
        public var memoryMaximumEntryCount: Int?
        /// The maximum storage byte count, or `nil` for no storage trim limit.
        public var storageMaximumByteCount: Int?

        /// Creates a cache configuration.
        public init(
            storageDirectory: URL,
            memoryMaximumCost: Int? = Self.defaultMemoryMaximumCost,
            memoryMaximumEntryCount: Int? = Self.defaultMemoryMaximumEntryCount,
            storageMaximumByteCount: Int? = Self.defaultStorageMaximumByteCount
        ) {
            self.storageDirectory = storageDirectory
            self.memoryMaximumCost = memoryMaximumCost.map { max(0, $0) }
            self.memoryMaximumEntryCount = memoryMaximumEntryCount.map { max(0, $0) }
            self.storageMaximumByteCount = storageMaximumByteCount.map { max(0, $0) }
        }
    }

    /// Per-operation cache options.
    public struct Options: Sendable, Equatable {
        /// An optional explicit memory cost override.
        public var cost: CacheCost?
        /// The lookup behavior for existing entries.
        public var lookupPolicy: CacheLookupPolicy
        /// The write behavior for generated values.
        public var writePolicy: CacheWritePolicy
        /// The read-failure behavior for recoverable cache corruption.
        public var readFailurePolicy: CacheReadFailurePolicy
        /// The write-failure behavior for cache storage failures.
        public var writeFailurePolicy: CacheWriteFailurePolicy
        /// The sharing behavior for concurrent misses.
        public var singleFlightPolicy: CacheSingleFlightPolicy

        /// Creates operation options.
        public init(
            cost: CacheCost? = nil,
            lookupPolicy: CacheLookupPolicy = .normal,
            writePolicy: CacheWritePolicy = .memoryAndStorage,
            readFailurePolicy: CacheReadFailurePolicy = .treatAsMiss,
            writeFailurePolicy: CacheWriteFailurePolicy = .throwError,
            singleFlightPolicy: CacheSingleFlightPolicy = .share
        ) {
            self.cost = cost
            self.lookupPolicy = lookupPolicy
            self.writePolicy = writePolicy
            self.readFailurePolicy = readFailurePolicy
            self.writeFailurePolicy = writeFailurePolicy
            self.singleFlightPolicy = singleFlightPolicy
        }

        /// Default options for ordinary cache work.
        public static let `default` = Options()
        /// Options for UI work whose callers may disappear while generating.
        public static let uiLifecycle = Options(
            writeFailurePolicy: .bestEffort,
            singleFlightPolicy: .cancelWhenNoWaiters
        )
    }

    /// A resolved cache value with source metadata.
    public struct Resolved<Value: Sendable>: Sendable {
        /// The resolved value.
        public let value: Value
        /// Where the value came from.
        public let source: Source
        /// Metadata for cached values when available.
        public let metadata: Metadata?
        /// Whether this caller joined an existing in-flight generation.
        public let wasSharedGeneration: Bool

        /// Creates a resolved value.
        public init(
            value: Value,
            source: Source,
            metadata: Metadata?,
            wasSharedGeneration: Bool
        ) {
            self.value = value
            self.source = source
            self.metadata = metadata
            self.wasSharedGeneration = wasSharedGeneration
        }
    }

    /// The source of a resolved value.
    public enum Source: Sendable, Equatable {
        /// The value came from memory.
        case memory
        /// The value came from file-backed storage.
        case storage
        /// The value was generated.
        case generated
    }

    /// Metadata for a cached entry.
    public struct Metadata: Sendable, Equatable {
        /// Encoded byte count in storage.
        public let byteCount: Int
        /// Memory cost recorded for the entry.
        public let cost: Int?
        /// Creation date for the stored entry.
        public let createdAt: Date
        /// Last storage access date.
        public let lastAccessedAt: Date
        /// Codec identifier stored with the entry.
        public let codecIdentifier: String

        /// Creates metadata.
        public init(
            byteCount: Int,
            cost: Int?,
            createdAt: Date,
            lastAccessedAt: Date,
            codecIdentifier: String
        ) {
            self.byteCount = byteCount
            self.cost = cost
            self.createdAt = createdAt
            self.lastAccessedAt = lastAccessedAt
            self.codecIdentifier = codecIdentifier
        }
    }

    /// Summary of file-backed storage usage.
    public struct StorageUsage: Sendable, Equatable {
        /// Total managed storage bytes.
        public let byteCount: Int
        /// Number of managed entries.
        public let entryCount: Int
        /// Configured storage budget, if any.
        public let maximumByteCount: Int?

        /// Creates a storage usage summary.
        public init(
            byteCount: Int,
            entryCount: Int,
            maximumByteCount: Int?
        ) {
            self.byteCount = byteCount
            self.entryCount = entryCount
            self.maximumByteCount = maximumByteCount
        }
    }

    /// Public Yashima errors.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// No cached value exists and generation was not allowed.
        case cacheMiss
        /// A cached in-memory value had an unexpected type.
        case valueTypeMismatch
    }

    /// A typed facade bound to one codec.
    public struct Typed<C: CacheCodec>: Sendable {
        /// The codec used by this facade.
        public let codec: C

        private let base: YCache

        fileprivate init(base: YCache, codec: C) {
            self.base = base
            self.codec = codec
        }

        /// Returns a cached value or generates, stores, and returns a new value.
        public func value(
            for key: CacheKey,
            options: Options = .default,
            _ generator: @escaping @Sendable () async throws -> C.Value
        ) async throws -> C.Value {
            try await base.value(
                for: key,
                codec: codec,
                options: options,
                generator
            )
        }

        /// Resolves a value and reports whether it came from memory, storage, or generation.
        public func resolve(
            for key: CacheKey,
            options: Options = .default,
            _ generator: @escaping @Sendable () async throws -> C.Value
        ) async throws -> Resolved<C.Value> {
            try await base.resolve(
                for: key,
                codec: codec,
                options: options,
                generator
            )
        }

        /// Returns a cached value if one is available.
        public func valueIfCached(for key: CacheKey) async throws -> C.Value? {
            try await base.valueIfCached(for: key, codec: codec)
        }

        /// Regenerates a value and updates the cache.
        public func refresh(
            for key: CacheKey,
            options: Options = .default,
            _ generator: @escaping @Sendable () async throws -> C.Value
        ) async throws -> C.Value {
            try await base.refresh(
                for: key,
                codec: codec,
                options: options,
                generator
            )
        }

        /// Returns an optional generated value without storing `nil` results.
        public func optionalValue(
            for key: CacheKey,
            options: Options = .default,
            _ generator: @escaping @Sendable () async throws -> C.Value?
        ) async throws -> C.Value? {
            try await base.optionalValue(
                for: key,
                codec: codec,
                options: options,
                generator
            )
        }

        /// Returns a memory value without reading storage.
        public func peek(for key: CacheKey) async throws -> C.Value? {
            try await base.peek(for: key, codec: codec)
        }

        /// Returns cache metadata without decoding the stored payload.
        public func metadata(for key: CacheKey) async throws -> Metadata? {
            try await base.metadata(for: key, codec: codec)
        }

        /// Returns whether memory or storage contains an entry for the key and codec.
        public func contains(for key: CacheKey) async throws -> Bool {
            try await base.contains(for: key, codec: codec)
        }

        /// Stores a value in memory without writing to storage.
        public func putInMemory(
            _ value: C.Value,
            for key: CacheKey,
            cost: CacheCost? = nil
        ) async throws {
            try await base.putInMemory(
                value,
                for: key,
                codec: codec,
                cost: cost
            )
        }

        /// Stores a value according to the supplied options.
        public func store(
            _ value: C.Value,
            for key: CacheKey,
            options: Options = .default
        ) async throws {
            try await base.store(
                value,
                for: key,
                codec: codec,
                options: options
            )
        }

        /// Removes the entry for a key from memory and storage.
        @discardableResult
        public func remove(for key: CacheKey) async throws -> Bool {
            try await base.remove(for: key, codec: codec)
        }
    }
}

private extension YCache {
    func resolvedIfCached<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options
    ) async throws -> Resolved<C.Value>? {
        var cacheOnlyOptions = options
        cacheOnlyOptions.lookupPolicy = .cacheOnly

        do {
            return try await resolve(
                for: key,
                codec: codec,
                options: cacheOnlyOptions
            ) {
                throw Error.cacheMiss
            }
        } catch Error.cacheMiss {
            return nil
        }
    }

    func storeResolved<C: CacheCodec>(
        _ value: C.Value,
        for key: CacheKey,
        codec: C,
        options: Options
    ) async throws -> Resolved<C.Value> {
        try await translateCoreErrors {
            let resolved = try await engine.store(
                value,
                for: key,
                codec: codec,
                options: options.coreOptions
            )
            return Resolved(resolved)
        }
    }

    func translateCoreErrors<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch CacheCoreError.cacheMiss {
            throw Error.cacheMiss
        } catch CacheCoreError.valueTypeMismatch {
            throw Error.valueTypeMismatch
        }
    }
}

// Private sentinel used only to route a nil optional generator result through
// the normal value pipeline, so it can reuse single-flight and cancellation.
private struct OptionalGenerationReturnedNil: Error {}

private extension YCache.Configuration {
    var memoryLimits: MemoryCacheStore.Limits {
        MemoryCacheStore.Limits(
            maximumCost: memoryMaximumCost,
            maximumEntryCount: memoryMaximumEntryCount
        )
    }
}

private extension YCache.Options {
    var coreOptions: CacheCoreOptions {
        CacheCoreOptions(
            cost: cost,
            lookupPolicy: lookupPolicy,
            writePolicy: writePolicy,
            readFailurePolicy: readFailurePolicy,
            writeFailurePolicy: writeFailurePolicy,
            singleFlightPolicy: singleFlightPolicy
        )
    }
}

private extension YCache.Resolved {
    init(_ resolved: CacheCoreResolved<Value>) {
        self.init(
            value: resolved.value,
            source: YCache.Source(resolved.source),
            metadata: resolved.metadata.map(YCache.Metadata.init),
            wasSharedGeneration: resolved.wasSharedGeneration
        )
    }
}

private extension YCache.Source {
    init(_ source: CacheCoreSource) {
        switch source {
        case .memory:
            self = .memory
        case .storage:
            self = .storage
        case .generated:
            self = .generated
        }
    }
}

private extension YCache.Metadata {
    init(_ metadata: CacheCoreMetadata) {
        self.init(
            byteCount: metadata.byteCount,
            cost: metadata.cost,
            createdAt: metadata.createdAt,
            lastAccessedAt: metadata.lastAccessedAt,
            codecIdentifier: metadata.codecIdentifier
        )
    }
}

private extension YCache.StorageUsage {
    init(_ usage: CacheCoreStorageUsage) {
        self.init(
            byteCount: usage.byteCount,
            entryCount: usage.entryCount,
            maximumByteCount: usage.maximumByteCount
        )
    }
}
