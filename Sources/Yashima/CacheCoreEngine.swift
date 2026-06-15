import Foundation

actor CacheCoreEngine {
    private let memory: MemoryCacheStore
    private let storage: StorageCacheStore
    private let now: @Sendable () -> Date
    private var inFlight: [CacheEntryIdentity: Task<AnyCacheCoreResolved, Error>] = [:]

    init(
        memory: MemoryCacheStore,
        storage: StorageCacheStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.memory = memory
        self.storage = storage
        self.now = now
    }

    func resolve<C: CacheCodec>(
        for key: CacheKey,
        codec: C,
        options: CacheCoreOptions = .default,
        generator: @escaping @Sendable () async throws -> C.Value
    ) async throws -> CacheCoreResolved<C.Value> {
        let identity = CacheEntryIdentity(key: key, codec: codec)

        if let task = inFlight[identity] {
            let resolved = try await task.value
            return try resolved.typed(as: C.Value.self, sharedFromInFlight: true)
        }

        let task = Task {
            try await Self.resolveWithoutSingleFlight(
                identity: identity,
                codec: codec,
                options: options,
                memory: memory,
                storage: storage,
                now: now,
                generator: generator
            )
        }
        inFlight[identity] = task
        defer {
            inFlight[identity] = nil
        }

        let resolved = try await task.value
        return try resolved.typed(as: C.Value.self, sharedFromInFlight: false)
    }

    func peekMemory<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> CacheCoreResolved<C.Value>? {
        let identity = CacheEntryIdentity(key: key, codec: codec)
        return try await Self.resolveFromMemory(
            identity: identity,
            memory: memory,
            as: C.Value.self
        )
    }

    @discardableResult
    func store<C: CacheCodec>(
        _ value: C.Value,
        for key: CacheKey,
        codec: C,
        options: CacheCoreOptions = .default
    ) async throws -> CacheCoreResolved<C.Value> {
        let identity = CacheEntryIdentity(key: key, codec: codec)
        return try await Self.storeGeneratedValue(
            value,
            identity: identity,
            codec: codec,
            options: options,
            memory: memory,
            storage: storage,
            now: now
        )
    }
}

struct CacheCoreOptions: Sendable, Equatable {
    var cost: CacheCost?
    var lookupPolicy: CacheLookupPolicy
    var writePolicy: CacheWritePolicy

    init(
        cost: CacheCost? = nil,
        lookupPolicy: CacheLookupPolicy = .normal,
        writePolicy: CacheWritePolicy = .memoryAndStorage
    ) {
        self.cost = cost
        self.lookupPolicy = lookupPolicy
        self.writePolicy = writePolicy
    }

    static let `default` = CacheCoreOptions()
}

public enum CacheLookupPolicy: Sendable, Equatable {
    case normal
    case cacheOnly
    case refresh
}

public enum CacheWritePolicy: Sendable, Equatable {
    case memoryAndStorage
    case memoryOnly
    case disabled
}

public enum CacheCost: Sendable, Equatable {
    case bytes(Int)
    case units(Int)
}

enum CacheCoreSource: Sendable, Equatable {
    case memory
    case storage
    case generated
}

struct CacheCoreMetadata: Sendable, Equatable {
    var byteCount: Int
    var cost: Int?
    var createdAt: Date
    var lastAccessedAt: Date
    var codecIdentifier: String

    init(_ metadata: StoredCacheEntryMetadata) {
        self.byteCount = metadata.byteCount
        self.cost = metadata.cost
        self.createdAt = metadata.createdAt
        self.lastAccessedAt = metadata.lastAccessedAt
        self.codecIdentifier = metadata.codecIdentifier
    }

    init(
        identity: CacheEntryIdentity,
        byteCount: Int,
        cost: Int?,
        date: Date
    ) {
        self.byteCount = byteCount
        self.cost = cost
        self.createdAt = date
        self.lastAccessedAt = date
        self.codecIdentifier = identity.codecIdentifier
    }
}

struct CacheCoreResolved<Value: Sendable>: Sendable {
    var value: Value
    var source: CacheCoreSource
    var metadata: CacheCoreMetadata?
    var wasSharedGeneration: Bool
}

enum CacheCoreError: Error, Equatable {
    case cacheMiss
    case valueTypeMismatch
}

private struct CacheCoreMemoryEntry<Value: Sendable>: Sendable {
    var value: Value
    var metadata: CacheCoreMetadata
}

private struct AnyCacheCoreResolved: Sendable {
    var value: any Sendable
    var source: CacheCoreSource
    var metadata: CacheCoreMetadata?
    var wasSharedGeneration: Bool

    init<Value: Sendable>(_ resolved: CacheCoreResolved<Value>) {
        self.value = resolved.value
        self.source = resolved.source
        self.metadata = resolved.metadata
        self.wasSharedGeneration = resolved.wasSharedGeneration
    }

    func typed<Value: Sendable>(
        as type: Value.Type,
        sharedFromInFlight: Bool
    ) throws -> CacheCoreResolved<Value> {
        guard let typedValue = value as? Value else {
            throw CacheCoreError.valueTypeMismatch
        }

        return CacheCoreResolved(
            value: typedValue,
            source: source,
            metadata: metadata,
            wasSharedGeneration: wasSharedGeneration || (sharedFromInFlight && source == .generated)
        )
    }
}

private extension CacheCoreEngine {
    static func resolveWithoutSingleFlight<C: CacheCodec>(
        identity: CacheEntryIdentity,
        codec: C,
        options: CacheCoreOptions,
        memory: MemoryCacheStore,
        storage: StorageCacheStore,
        now: @escaping @Sendable () -> Date,
        generator: @escaping @Sendable () async throws -> C.Value
    ) async throws -> AnyCacheCoreResolved {
        if options.lookupPolicy.readsMemory {
            if let resolved = try await resolveFromMemory(
                identity: identity,
                memory: memory,
                as: C.Value.self
            ) {
                return AnyCacheCoreResolved(resolved)
            }
        }

        if options.lookupPolicy.readsStorage,
           let resolved = try await resolveFromStorage(
            identity: identity,
            codec: codec,
            options: options,
            memory: memory,
            storage: storage
           ) {
            return AnyCacheCoreResolved(resolved)
        }

        guard options.lookupPolicy.allowsGeneration else {
            throw CacheCoreError.cacheMiss
        }

        let value = try await generator()
        let resolved = try await storeGeneratedValue(
            value,
            identity: identity,
            codec: codec,
            options: options,
            memory: memory,
            storage: storage,
            now: now
        )
        return AnyCacheCoreResolved(resolved)
    }

    static func resolveFromMemory<Value: Sendable>(
        identity: CacheEntryIdentity,
        memory: MemoryCacheStore,
        as type: Value.Type
    ) async throws -> CacheCoreResolved<Value>? {
        if let entry = await memory.peek(
            for: identity,
            as: CacheCoreMemoryEntry<Value>.self
        ) {
            return CacheCoreResolved(
                value: entry.value,
                source: .memory,
                metadata: entry.metadata,
                wasSharedGeneration: false
            )
        }

        if await memory.containsValue(for: identity) {
            throw CacheCoreError.valueTypeMismatch
        }

        return nil
    }

    static func resolveFromStorage<C: CacheCodec>(
        identity: CacheEntryIdentity,
        codec: C,
        options: CacheCoreOptions,
        memory: MemoryCacheStore,
        storage: StorageCacheStore
    ) async throws -> CacheCoreResolved<C.Value>? {
        guard let stored = try await storage.loadData(for: identity) else {
            return nil
        }

        let value = try codec.decode(stored.data)
        let metadata = CacheCoreMetadata(stored.metadata)
        if options.writePolicy.writesMemory {
            await memory.put(
                CacheCoreMemoryEntry(value: value, metadata: metadata),
                for: identity,
                cost: metadata.memoryCost
            )
        }

        return CacheCoreResolved(
            value: value,
            source: .storage,
            metadata: metadata,
            wasSharedGeneration: false
        )
    }

    static func storeGeneratedValue<C: CacheCodec>(
        _ value: C.Value,
        identity: CacheEntryIdentity,
        codec: C,
        options: CacheCoreOptions,
        memory: MemoryCacheStore,
        storage: StorageCacheStore,
        now: @escaping @Sendable () -> Date
    ) async throws -> CacheCoreResolved<C.Value> {
        let encodedData = try encodedDataIfNeeded(
            value,
            codec: codec,
            writePolicy: options.writePolicy
        )

        let metadata: CacheCoreMetadata?
        if options.writePolicy.writesStorage, let encodedData {
            let storedMetadata = try await storage.store(
                encodedData,
                for: identity,
                cost: options.cost?.value
            )
            metadata = CacheCoreMetadata(storedMetadata)
        } else if let encodedData {
            metadata = CacheCoreMetadata(
                identity: identity,
                byteCount: encodedData.count,
                cost: options.cost?.value,
                date: now()
            )
        } else {
            metadata = nil
        }

        if options.writePolicy.writesMemory, let metadata {
            await memory.put(
                CacheCoreMemoryEntry(value: value, metadata: metadata),
                for: identity,
                cost: metadata.memoryCost
            )
        }

        return CacheCoreResolved(
            value: value,
            source: .generated,
            metadata: metadata,
            wasSharedGeneration: false
        )
    }

    static func encodedDataIfNeeded<C: CacheCodec>(
        _ value: C.Value,
        codec: C,
        writePolicy: CacheWritePolicy
    ) throws -> Data? {
        guard writePolicy.writesMemory || writePolicy.writesStorage else {
            return nil
        }

        return try codec.encode(value)
    }
}

private extension CacheLookupPolicy {
    var readsMemory: Bool {
        switch self {
        case .normal, .cacheOnly:
            true
        case .refresh:
            false
        }
    }

    var readsStorage: Bool {
        switch self {
        case .normal, .cacheOnly:
            true
        case .refresh:
            false
        }
    }

    var allowsGeneration: Bool {
        switch self {
        case .normal, .refresh:
            true
        case .cacheOnly:
            false
        }
    }
}

private extension CacheWritePolicy {
    var writesMemory: Bool {
        switch self {
        case .memoryAndStorage, .memoryOnly:
            true
        case .disabled:
            false
        }
    }

    var writesStorage: Bool {
        switch self {
        case .memoryAndStorage:
            true
        case .memoryOnly, .disabled:
            false
        }
    }
}

private extension CacheCost {
    var value: Int {
        switch self {
        case let .bytes(value), let .units(value):
            max(0, value)
        }
    }
}

private extension CacheCoreMetadata {
    var memoryCost: Int {
        cost ?? byteCount
    }
}
