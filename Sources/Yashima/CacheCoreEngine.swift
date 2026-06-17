import Foundation

actor CacheCoreEngine {
    private let memory: MemoryCacheStore
    private let storage: StorageCacheStore
    private let now: @Sendable () -> Date
    private var inFlight: [CacheInFlightIdentity: CacheInFlightEntry] = [:]
    private var nextInFlightToken = 0

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
        let inFlightIdentity = CacheInFlightIdentity(
            entryIdentity: identity,
            policy: options.singleFlightPolicy
        )

        guard options.singleFlightPolicy.sharesGeneration else {
            let resolved = try await Self.resolveWithoutSingleFlight(
                identity: identity,
                codec: codec,
                options: options,
                memory: memory,
                storage: storage,
                now: now,
                generator: generator
            )
            return try resolved.typed(as: C.Value.self, sharedFromInFlight: false)
        }

        let waiterID = UUID()
        let registration = CacheInFlightWaiterRegistration()

        let waiterResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    self.joinOrStartInFlight(
                        inFlightIdentity,
                        waiterID: waiterID,
                        registration: registration,
                        continuation: continuation,
                        codec: codec,
                        options: options,
                        memory: memory,
                        storage: storage,
                        now: now,
                        generator: generator
                    )
                }
            }
        } onCancel: {
            if registration.cancel() {
                Task {
                    await self.cancelInFlightWaiter(waiterID, for: inFlightIdentity)
                }
            }
        }

        return try waiterResult.resolved.typed(
            as: C.Value.self,
            sharedFromInFlight: waiterResult.sharedFromInFlight
        )
    }

    private func joinOrStartInFlight<C: CacheCodec>(
        _ inFlightIdentity: CacheInFlightIdentity,
        waiterID: UUID,
        registration: CacheInFlightWaiterRegistration,
        continuation: CheckedContinuation<CacheInFlightWaiterResult, any Error>,
        codec: C,
        options: CacheCoreOptions,
        memory: MemoryCacheStore,
        storage: StorageCacheStore,
        now: @escaping @Sendable () -> Date,
        generator: @escaping @Sendable () async throws -> C.Value
    ) {
        guard registration.markRegistered() else {
            continuation.resume(throwing: CancellationError())
            return
        }

        let waiter = CacheInFlightWaiter(
            continuation: continuation,
            sharedFromInFlight: inFlight[inFlightIdentity] != nil
        )

        if var entry = inFlight[inFlightIdentity] {
            entry.waiters[waiterID] = waiter
            inFlight[inFlightIdentity] = entry
            return
        }

        nextInFlightToken += 1
        let token = CacheInFlightToken(rawValue: nextInFlightToken)
        let task = Task {
            try await Self.resolveWithoutSingleFlight(
                identity: inFlightIdentity.entryIdentity,
                codec: codec,
                options: options,
                memory: memory,
                storage: storage,
                now: now,
                generator: generator
            )
        }

        inFlight[inFlightIdentity] = CacheInFlightEntry(
            token: token,
            policy: options.singleFlightPolicy,
            task: task,
            waiters: [waiterID: waiter]
        )

        Task {
            let result: Result<AnyCacheCoreResolved, any Error>
            do {
                result = .success(try await task.value)
            } catch {
                result = .failure(error)
            }
            self.finishInFlight(inFlightIdentity, token: token, result: result)
        }
    }

    private func cancelInFlightWaiter(
        _ waiterID: UUID,
        for inFlightIdentity: CacheInFlightIdentity
    ) {
        guard var entry = inFlight[inFlightIdentity],
              let waiter = entry.waiters.removeValue(forKey: waiterID) else {
            return
        }

        waiter.continuation.resume(throwing: CancellationError())

        if entry.policy.cancelsProducerWhenNoWaiters && entry.waiters.isEmpty {
            inFlight[inFlightIdentity] = nil
            entry.task.cancel()
        } else {
            inFlight[inFlightIdentity] = entry
        }
    }

    private func finishInFlight(
        _ inFlightIdentity: CacheInFlightIdentity,
        token: CacheInFlightToken,
        result: Result<AnyCacheCoreResolved, any Error>
    ) {
        guard let entry = inFlight[inFlightIdentity],
              entry.token == token else {
            return
        }

        inFlight[inFlightIdentity] = nil

        for waiter in entry.waiters.values {
            switch result {
            case .success(let resolved):
                waiter.continuation.resume(
                    returning: CacheInFlightWaiterResult(
                        resolved: resolved,
                        sharedFromInFlight: waiter.sharedFromInFlight
                    )
                )
            case .failure(let error):
                waiter.continuation.resume(throwing: error)
            }
        }
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
    var singleFlightPolicy: CacheSingleFlightPolicy

    init(
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

public enum CacheSingleFlightPolicy: Sendable, Hashable {
    case share
    case cancelWhenNoWaiters
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

private struct CacheInFlightIdentity: Sendable, Hashable {
    var entryIdentity: CacheEntryIdentity
    var policy: CacheSingleFlightPolicy
}

private struct CacheInFlightToken: Sendable, Hashable {
    var rawValue: Int
}

private struct CacheInFlightEntry {
    var token: CacheInFlightToken
    var policy: CacheSingleFlightPolicy
    var task: Task<AnyCacheCoreResolved, any Error>
    var waiters: [UUID: CacheInFlightWaiter]
}

private struct CacheInFlightWaiter {
    var continuation: CheckedContinuation<CacheInFlightWaiterResult, any Error>
    var sharedFromInFlight: Bool
}

private struct CacheInFlightWaiterResult: Sendable {
    var resolved: AnyCacheCoreResolved
    var sharedFromInFlight: Bool
}

private final class CacheInFlightWaiterRegistration: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var isRegistered = false

    func markRegistered() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isCancelled else {
            return false
        }

        isRegistered = true
        return true
    }

    func cancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        isCancelled = true
        return isRegistered
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
        try Task.checkCancellation()

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

        var storedMetadata: CacheCoreMetadata?
        let value = try await generator()
        try Task.checkCancellation()
        let resolved = try await storeGeneratedValue(
            value,
            identity: identity,
            codec: codec,
            options: options,
            memory: memory,
            storage: storage,
            now: now
        )
        storedMetadata = resolved.metadata
        do {
            try Task.checkCancellation()
        } catch is CancellationError {
            if storedMetadata != nil {
                await memory.removeValue(for: identity)
                _ = try? await storage.removeValue(for: identity)
            }
            throw CancellationError()
        }
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
        let memoryCost = cacheCost(
            for: value,
            codec: codec,
            encodedData: stored.data,
            options: options,
            metadata: metadata
        )
        if options.writePolicy.writesMemory {
            await memory.put(
                CacheCoreMemoryEntry(value: value, metadata: metadata),
                for: identity,
                cost: memoryCost
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
        var wroteStorage = false
        var wroteMemory = false

        do {
            try Task.checkCancellation()
            let encodedData = try encodedDataIfNeeded(
                value,
                codec: codec,
                writePolicy: options.writePolicy
            )
            try Task.checkCancellation()

            let metadata: CacheCoreMetadata?
            if options.writePolicy.writesStorage, let encodedData {
                let cost = cacheCost(
                    for: value,
                    codec: codec,
                    encodedData: encodedData,
                    options: options
                )
                do {
                    let storedMetadata = try await storage.store(
                        encodedData,
                        for: identity,
                        cost: cost
                    )
                    wroteStorage = true
                    try Task.checkCancellation()
                    metadata = CacheCoreMetadata(storedMetadata)
                } catch {
                    if error is CancellationError {
                        throw error
                    }
                    guard options.writeFailurePolicy.allowsBestEffortStorageFailure else {
                        throw error
                    }
                    metadata = CacheCoreMetadata(
                        identity: identity,
                        byteCount: encodedData.count,
                        cost: cost,
                        date: now()
                    )
                }
            } else if let encodedData {
                let cost = cacheCost(
                    for: value,
                    codec: codec,
                    encodedData: encodedData,
                    options: options
                )
                metadata = CacheCoreMetadata(
                    identity: identity,
                    byteCount: encodedData.count,
                    cost: cost,
                    date: now()
                )
            } else {
                metadata = nil
            }

            if options.writePolicy.writesMemory, let metadata {
                try Task.checkCancellation()
                await memory.put(
                    CacheCoreMemoryEntry(value: value, metadata: metadata),
                    for: identity,
                    cost: metadata.memoryCost
                )
                wroteMemory = true
                try Task.checkCancellation()
            }

            return CacheCoreResolved(
                value: value,
                source: .generated,
                metadata: metadata,
                wasSharedGeneration: false
            )
        } catch is CancellationError {
            if wroteMemory {
                await memory.removeValue(for: identity)
            }
            if wroteStorage {
                _ = try? await storage.removeValue(for: identity)
            }
            throw CancellationError()
        }
    }

    static func cacheCost<C: CacheCodec>(
        for value: C.Value,
        codec: C,
        encodedData: Data,
        options: CacheCoreOptions
    ) -> Int? {
        if let explicitCost = options.cost?.value {
            return explicitCost
        }

        return (codec as? any CacheMemoryCostEstimating)?
            .estimatedMemoryCost(for: value, encodedData: encodedData)
    }

    static func cacheCost<C: CacheCodec>(
        for value: C.Value,
        codec: C,
        encodedData: Data,
        options: CacheCoreOptions,
        metadata: CacheCoreMetadata
    ) -> Int {
        if let resolvedCost = cacheCost(
            for: value,
            codec: codec,
            encodedData: encodedData,
            options: options
        ) {
            return resolvedCost
        }

        return metadata.memoryCost
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

private extension CacheSingleFlightPolicy {
    var sharesGeneration: Bool {
        switch self {
        case .share, .cancelWhenNoWaiters:
            true
        case .disabled:
            false
        }
    }

    var cancelsProducerWhenNoWaiters: Bool {
        switch self {
        case .cancelWhenNoWaiters:
            true
        case .share, .disabled:
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
