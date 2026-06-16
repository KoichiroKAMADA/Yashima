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

    func metadata<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> CacheCoreMetadata? {
        let identity = CacheEntryIdentity(key: key, codec: codec)
        if let metadata = await memory.peekMetadata(for: identity) {
            return metadata
        }

        return try await Self.metadataFromStorage(identity: identity, storage: storage)
    }

    func contains<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        let identity = CacheEntryIdentity(key: key, codec: codec)
        if await memory.containsValue(for: identity) {
            return true
        }

        return try await Self.metadataFromStorage(identity: identity, storage: storage) != nil
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

    @discardableResult
    func remove<C: CacheCodec>(
        for key: CacheKey,
        codec: C
    ) async throws -> Bool {
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let removedFromMemory = await memory.removeValue(for: identity)
        let removedFromStorage = try await storage.removeValue(for: identity)
        return removedFromMemory || removedFromStorage
    }

    func removeAll() async throws {
        await memory.removeAll()
        try await storage.removeAll()
    }

    func removeAll(in namespace: String) async throws {
        await memory.removeAll(in: namespace)
        try await storage.removeAll(in: namespace)
    }

    func storageUsage() async throws -> CacheCoreStorageUsage {
        CacheCoreStorageUsage(try await storage.usage())
    }

    @discardableResult
    func trimStorageIfNeeded() async throws -> CacheCoreStorageUsage {
        CacheCoreStorageUsage(try await storage.trimIfNeeded())
    }
}

struct CacheCoreOptions: Sendable, Equatable {
    var cost: CacheCost?
    var lookupPolicy: CacheLookupPolicy
    var writePolicy: CacheWritePolicy
    var readFailurePolicy: CacheReadFailurePolicy
    var writeFailurePolicy: CacheWriteFailurePolicy

    init(
        cost: CacheCost? = nil,
        lookupPolicy: CacheLookupPolicy = .normal,
        writePolicy: CacheWritePolicy = .memoryAndStorage,
        readFailurePolicy: CacheReadFailurePolicy = .treatAsMiss,
        writeFailurePolicy: CacheWriteFailurePolicy = .throwError
    ) {
        self.cost = cost
        self.lookupPolicy = lookupPolicy
        self.writePolicy = writePolicy
        self.readFailurePolicy = readFailurePolicy
        self.writeFailurePolicy = writeFailurePolicy
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

public enum CacheReadFailurePolicy: Sendable, Equatable {
    case throwError
    case treatAsMiss
}

public enum CacheWriteFailurePolicy: Sendable, Equatable {
    case throwError
    case bestEffort
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

struct CacheCoreStorageUsage: Sendable, Equatable {
    var byteCount: Int
    var entryCount: Int
    var maximumByteCount: Int?

    init(_ usage: StorageCacheUsage) {
        self.byteCount = usage.byteCount
        self.entryCount = usage.entryCount
        self.maximumByteCount = usage.maximumByteCount
    }
}

enum CacheCoreError: Error, Equatable {
    case cacheMiss
    case valueTypeMismatch
}

protocol CacheCoreMemoryMetadataProviding: Sendable {
    var cacheCoreMetadata: CacheCoreMetadata { get }
}

private struct CacheCoreMemoryEntry<Value: Sendable>: Sendable {
    var value: Value
    var metadata: CacheCoreMetadata
}

extension CacheCoreMemoryEntry: CacheCoreMemoryMetadataProviding {
    var cacheCoreMetadata: CacheCoreMetadata {
        metadata
    }
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

    static func metadataFromStorage(
        identity: CacheEntryIdentity,
        storage: StorageCacheStore
    ) async throws -> CacheCoreMetadata? {
        do {
            guard let metadata = try await storage.metadata(for: identity) else {
                return nil
            }
            return CacheCoreMetadata(metadata)
        } catch {
            if isRecoverableStorageReadFailure(error) {
                return nil
            }
            throw error
        }
    }

    static func resolveFromStorage<C: CacheCodec>(
        identity: CacheEntryIdentity,
        codec: C,
        options: CacheCoreOptions,
        memory: MemoryCacheStore,
        storage: StorageCacheStore
    ) async throws -> CacheCoreResolved<C.Value>? {
        let stored: StoredCacheEntry
        do {
            guard let loaded = try await storage.loadData(for: identity) else {
                return nil
            }
            stored = loaded
        } catch {
            if options.readFailurePolicy.treatsReadFailureAsMiss,
               isRecoverableStorageReadFailure(error) {
                return nil
            }
            throw error
        }

        let value: C.Value
        do {
            value = try codec.decode(stored.data)
        } catch {
            _ = try? await storage.removeValue(for: identity)
            if options.readFailurePolicy.treatsReadFailureAsMiss {
                return nil
            }
            throw error
        }

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
            do {
                let storedMetadata = try await storage.store(
                    encodedData,
                    for: identity,
                    cost: options.cost?.value
                )
                metadata = CacheCoreMetadata(storedMetadata)
            } catch {
                guard options.writeFailurePolicy.allowsBestEffortStorageFailure else {
                    throw error
                }
                metadata = CacheCoreMetadata(
                    identity: identity,
                    byteCount: encodedData.count,
                    cost: options.cost?.value,
                    date: now()
                )
            }
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

    static func isRecoverableStorageReadFailure(_ error: any Error) -> Bool {
        error is StorageCacheStoreError || error is DecodingError
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

private extension CacheReadFailurePolicy {
    var treatsReadFailureAsMiss: Bool {
        switch self {
        case .throwError:
            false
        case .treatAsMiss:
            true
        }
    }
}

private extension CacheWriteFailurePolicy {
    var allowsBestEffortStorageFailure: Bool {
        switch self {
        case .throwError:
            false
        case .bestEffort:
            true
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
