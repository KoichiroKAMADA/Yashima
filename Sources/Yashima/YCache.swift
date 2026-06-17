import Foundation

public final class YCache: Sendable {
    public let configuration: Configuration

    private let engine: CacheCoreEngine

    public init(configuration: Configuration) {
        self.configuration = configuration
        let memory = MemoryCacheStore(limits: configuration.memoryLimits)
        let storage = StorageCacheStore(
            rootDirectory: configuration.storageDirectory,
            maximumByteCount: configuration.storageMaximumByteCount
        )
        self.engine = CacheCoreEngine(memory: memory, storage: storage)
    }

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

    public func using<C: CacheCodec>(_ codec: C) -> Typed<C> {
        Typed(base: self, codec: codec)
    }

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

    public func valueIfCached<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> C.Value? {
        try await resolvedIfCached(for: key, codec: codec, options: .default)?.value
    }

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

    public func optionalValue<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: Options = .default,
        _ generator: @escaping @Sendable () async throws -> C.Value?
    ) async throws -> C.Value? {
        switch options.lookupPolicy {
        case .normal:
            if let cached = try await resolvedIfCached(
                for: key,
                codec: codec,
                options: options
            )?.value {
                return cached
            }
        case .cacheOnly:
            return try await resolvedIfCached(
                for: key,
                codec: codec,
                options: options
            )?.value
        case .refresh:
            break
        }

        guard let value = try await generator() else {
            return nil
        }

        var generationOptions = options
        generationOptions.lookupPolicy = .refresh
        return try await self.value(
            for: key,
            codec: codec,
            options: generationOptions
        ) {
            value
        }
    }

    public func peek<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> C.Value? {
        try await translateCoreErrors {
            let resolved = try await engine.peekMemory(for: key, codec: codec)
            return resolved?.value
        }
    }

    public func metadata<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Metadata? {
        try await translateCoreErrors {
            try await engine.metadata(for: key, codec: codec).map(Metadata.init)
        }
    }

    public func contains<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        try await translateCoreErrors {
            try await engine.contains(for: key, codec: codec)
        }
    }

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

    public func store<C: CacheCodec>(
        _ value: C.Value,
        for key: CacheKey,
        codec: C,
        options: Options = .default
    ) async throws {
        _ = try await storeResolved(value, for: key, codec: codec, options: options)
    }

    @discardableResult
    public func remove<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        try await translateCoreErrors {
            try await engine.remove(for: key, codec: codec)
        }
    }

    public func removeAll() async throws {
        try await translateCoreErrors {
            try await engine.removeAll()
        }
    }

    public func removeAll(in namespace: String) async throws {
        try await translateCoreErrors {
            try await engine.removeAll(in: namespace)
        }
    }

    public func storageUsage() async throws -> StorageUsage {
        try await translateCoreErrors {
            StorageUsage(try await engine.storageUsage())
        }
    }

    @discardableResult
    public func trimStorageIfNeeded() async throws -> StorageUsage {
        try await translateCoreErrors {
            StorageUsage(try await engine.trimStorageIfNeeded())
        }
    }
}

extension YCache {
    public struct Configuration: Sendable, Equatable {
        public static let defaultMemoryMaximumCost = 64 * 1024 * 1024
        public static let defaultMemoryMaximumEntryCount: Int? = nil
        public static let defaultStorageMaximumByteCount = 128 * 1024 * 1024

        public var storageDirectory: URL
        public var memoryMaximumCost: Int?
        public var memoryMaximumEntryCount: Int?
        public var storageMaximumByteCount: Int?

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

    public struct Options: Sendable, Equatable {
        public var cost: CacheCost?
        public var lookupPolicy: CacheLookupPolicy
        public var writePolicy: CacheWritePolicy
        public var readFailurePolicy: CacheReadFailurePolicy
        public var writeFailurePolicy: CacheWriteFailurePolicy
        public var singleFlightPolicy: CacheSingleFlightPolicy

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

        public static let `default` = Options()
    }

    public struct Resolved<Value: Sendable>: Sendable {
        public let value: Value
        public let source: Source
        public let metadata: Metadata?
        public let wasSharedGeneration: Bool

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

    public enum Source: Sendable, Equatable {
        case memory
        case storage
        case generated
    }

    public struct Metadata: Sendable, Equatable {
        public let byteCount: Int
        public let cost: Int?
        public let createdAt: Date
        public let lastAccessedAt: Date
        public let codecIdentifier: String

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

    public struct StorageUsage: Sendable, Equatable {
        public let byteCount: Int
        public let entryCount: Int
        public let maximumByteCount: Int?

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

    public enum Error: Swift.Error, Sendable, Equatable {
        case cacheMiss
        case valueTypeMismatch
    }

    public struct Typed<C: CacheCodec>: Sendable {
        public let codec: C

        private let base: YCache

        fileprivate init(base: YCache, codec: C) {
            self.base = base
            self.codec = codec
        }

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

        public func valueIfCached(for key: CacheKey) async throws -> C.Value? {
            try await base.valueIfCached(for: key, codec: codec)
        }

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

        public func peek(for key: CacheKey) async throws -> C.Value? {
            try await base.peek(for: key, codec: codec)
        }

        public func metadata(for key: CacheKey) async throws -> Metadata? {
            try await base.metadata(for: key, codec: codec)
        }

        public func contains(for key: CacheKey) async throws -> Bool {
            try await base.contains(for: key, codec: codec)
        }

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
