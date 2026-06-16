import Foundation
import Testing
@testable import Yashima

@Test func coreEngineReturnsMemoryHitWithoutStorageOrGenerator() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("memory-hit")
        let codec = UTF8StringCodec()

        let generated = try await engine.resolve(for: key, codec: codec) {
            "cached"
        }
        try await storage.removeAll()

        let counter = CallCounter()
        let resolved = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "regenerated"
        }

        #expect(generated.source == .generated)
        #expect(resolved.value == "cached")
        #expect(resolved.source == .memory)
        #expect(await counter.count == 0)
    }
}

@Test func coreEngineReturnsStorageHitWithoutGeneratorAndPromotesToMemory() async throws {
    try await withCoreEngine { engine, memory, storage, _ in
        let key = coreKey("storage-hit")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        try await storage.store(Data("stored".utf8), for: identity, cost: 6)

        let counter = CallCounter()
        let resolved = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "generated"
        }

        try await storage.removeAll()
        let promoted = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "regenerated"
        }
        let snapshot = await memory.snapshot()

        #expect(resolved.value == "stored")
        #expect(resolved.source == .storage)
        #expect(promoted.value == "stored")
        #expect(promoted.source == .memory)
        #expect(snapshot.entryCount == 1)
        #expect(snapshot.totalCost == 6)
        #expect(await counter.count == 0)
    }
}

@Test func coreEngineGeneratesOnceOnFullMissAndStoresValue() async throws {
    try await withCoreEngine { engine, _, storage, rootDirectory in
        let key = coreKey("full-miss")
        let codec = UTF8StringCodec()
        let counter = CallCounter()

        let resolved = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "fresh"
        }

        let newMemory = MemoryCacheStore()
        let newStorage = StorageCacheStore(rootDirectory: rootDirectory)
        let newEngine = CacheCoreEngine(memory: newMemory, storage: newStorage)
        let persisted = try await newEngine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "regenerated"
        }
        let storageLocation = await storage.location(for: CacheEntryIdentity(key: key, codec: codec))

        #expect(resolved.value == "fresh")
        #expect(resolved.source == .generated)
        #expect(persisted.value == "fresh")
        #expect(persisted.source == .storage)
        #expect(fileExists(at: storageLocation.dataURL))
        #expect(fileExists(at: storageLocation.metadataURL))
        #expect(await counter.count == 1)
    }
}

@Test func coreEngineCoalescesConcurrentRequestsWithSingleFlight() async throws {
    try await withCoreEngine { engine, _, _, _ in
        let key = coreKey("single-flight")
        let codec = UTF8StringCodec()
        let counter = CallCounter()

        let resolvedValues = try await withThrowingTaskGroup(of: CacheCoreResolved<String>.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await engine.resolve(for: key, codec: codec) {
                        let invocation = await counter.increment()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return "shared-\(invocation)"
                    }
                }
            }

            var results: [CacheCoreResolved<String>] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        #expect(resolvedValues.count == 20)
        #expect(resolvedValues.allSatisfy { $0.value == "shared-1" })
        #expect(resolvedValues.allSatisfy { $0.source == .generated })
        #expect(resolvedValues.contains { $0.wasSharedGeneration })
        #expect(await counter.count == 1)
    }
}

@Test func coreEngineDoesNotSaveWhenGeneratorThrows() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("throwing-generator")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)

        do {
            _ = try await engine.resolve(for: key, codec: codec) {
                throw CoreEngineTestError.generator
            }
            Issue.record("Expected generator error to be thrown.")
        } catch CoreEngineTestError.generator {
        }

        let stored = try await storage.loadData(for: identity)
        #expect(stored == nil)

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                "should-not-run"
            }
            Issue.record("Expected cache miss after generator failure.")
        } catch CacheCoreError.cacheMiss {
        }
    }
}

@Test func coreEngineCacheOnlyPolicyDoesNotRunGenerator() async throws {
    try await withCoreEngine { engine, _, _, _ in
        let counter = CallCounter()

        do {
            _ = try await engine.resolve(
                for: coreKey("cache-only-miss"),
                codec: UTF8StringCodec(),
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                await counter.increment()
                return "generated"
            }
            Issue.record("Expected cache-only miss to throw.")
        } catch CacheCoreError.cacheMiss {
        }

        #expect(await counter.count == 0)
    }
}

@Test func coreEngineRefreshPolicyBypassesExistingCache() async throws {
    try await withCoreEngine { engine, _, _, _ in
        let key = coreKey("refresh")
        let codec = UTF8StringCodec()

        _ = try await engine.resolve(for: key, codec: codec) {
            "old"
        }

        let refreshed = try await engine.resolve(
            for: key,
            codec: codec,
            options: .init(lookupPolicy: .refresh)
        ) {
            "new"
        }
        let cachedAgain = try await engine.resolve(for: key, codec: codec) {
            "unused"
        }

        #expect(refreshed.value == "new")
        #expect(refreshed.source == .generated)
        #expect(cachedAgain.value == "new")
        #expect(cachedAgain.source == .memory)
    }
}

@Test func coreEngineMemoryOnlyWritePolicyDoesNotPersistToStorage() async throws {
    try await withCoreEngine { engine, _, _, rootDirectory in
        let key = coreKey("memory-only")
        let codec = UTF8StringCodec()

        let generated = try await engine.resolve(
            for: key,
            codec: codec,
            options: .init(writePolicy: .memoryOnly)
        ) {
            "memory"
        }
        let memoryHit = try await engine.resolve(for: key, codec: codec) {
            "unused"
        }

        let newEngine = CacheCoreEngine(
            memory: MemoryCacheStore(),
            storage: StorageCacheStore(rootDirectory: rootDirectory)
        )

        do {
            _ = try await newEngine.resolve(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                "should-not-run"
            }
            Issue.record("Expected memory-only entry not to exist in storage.")
        } catch CacheCoreError.cacheMiss {
        }

        #expect(generated.source == .generated)
        #expect(memoryHit.value == "memory")
        #expect(memoryHit.source == .memory)
    }
}

@Test func coreEngineDisabledWritePolicyDoesNotEncodeOrCache() async throws {
    try await withCoreEngine { engine, _, _, _ in
        let key = coreKey("write-disabled")
        let codec = ThrowingEncodeStringCodec()

        let resolved = try await engine.resolve(
            for: key,
            codec: codec,
            options: .init(writePolicy: .disabled)
        ) {
            "transient"
        }

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                "should-not-run"
            }
            Issue.record("Expected disabled write policy not to cache value.")
        } catch CacheCoreError.cacheMiss {
        }

        #expect(resolved.value == "transient")
        #expect(resolved.source == .generated)
        #expect(resolved.metadata == nil)
    }
}

@Test func coreEnginePropagatesDecodeFailureFromStorageHit() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("decode-failure")
        let codec = ThrowingDecodeStringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let counter = CallCounter()
        try await storage.store(Data("not-decodable".utf8), for: identity)

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(readFailurePolicy: .throwError)
            ) {
                await counter.increment()
                return "generated"
            }
            Issue.record("Expected decode error to be thrown.")
        } catch CoreEngineTestError.decode {
        }

        #expect(await counter.count == 0)
    }
}

@Test func coreEngineTreatsDecodeFailureAsMissByDefault() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("decode-failure-as-miss")
        let codec = ThrowingDecodeStringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let counter = CallCounter()
        try await storage.store(Data("not-decodable".utf8), for: identity)

        let resolved = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "generated"
        }
        let storedAfterDecodeFailure = try await storage.loadData(for: identity)

        #expect(resolved.value == "generated")
        #expect(resolved.source == .generated)
        #expect(storedAfterDecodeFailure?.data == Data("generated".utf8))
        #expect(await counter.count == 1)
    }
}

@Test func coreEngineTreatsCorruptedStorageAsMissByDefault() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("corrupted-storage-as-miss")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let location = await storage.location(for: identity)
        let counter = CallCounter()

        try await storage.store(Data("old".utf8), for: identity)
        try Data("tampered".utf8).write(to: location.dataURL)

        let resolved = try await engine.resolve(for: key, codec: codec) {
            await counter.increment()
            return "new"
        }
        let stored = try await storage.loadData(for: identity)

        #expect(resolved.value == "new")
        #expect(resolved.source == .generated)
        #expect(stored?.data == Data("new".utf8))
        #expect(await counter.count == 1)
    }
}

@Test func coreEnginePropagatesCorruptedStorageWhenPolicyThrows() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("corrupted-storage-throws")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let location = await storage.location(for: identity)
        let counter = CallCounter()

        try await storage.store(Data("old".utf8), for: identity)
        try Data("tampered".utf8).write(to: location.dataURL)

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(readFailurePolicy: .throwError)
            ) {
                await counter.increment()
                return "new"
            }
            Issue.record("Expected corrupted storage to throw.")
        } catch StorageCacheStoreError.dataMismatch {
        }

        #expect(await counter.count == 0)
    }
}

@Test func coreEngineCacheOnlyTreatsCorruptedStorageAsMissWithoutGenerating() async throws {
    try await withCoreEngine { engine, _, storage, _ in
        let key = coreKey("cache-only-corruption")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let location = await storage.location(for: identity)
        let counter = CallCounter()

        try await storage.store(Data("old".utf8), for: identity)
        try Data("tampered".utf8).write(to: location.dataURL)

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                await counter.increment()
                return "new"
            }
            Issue.record("Expected cache-only corrupted storage to miss.")
        } catch CacheCoreError.cacheMiss {
        }

        let stored = try await storage.loadData(for: identity)

        #expect(stored == nil)
        #expect(await counter.count == 0)
    }
}

@Test func coreEnginePropagatesMemoryTypeMismatch() async throws {
    try await withCoreEngine { engine, memory, _, _ in
        let key = coreKey("memory-type-mismatch")
        let codec = UTF8StringCodec()
        let identity = CacheEntryIdentity(key: key, codec: codec)
        let counter = CallCounter()

        await memory.put(123, for: identity)

        do {
            _ = try await engine.resolve(for: key, codec: codec) {
                await counter.increment()
                return "generated"
            }
            Issue.record("Expected memory type mismatch to throw.")
        } catch CacheCoreError.valueTypeMismatch {
        }

        #expect(await counter.count == 0)
    }
}

@Test func coreEnginePropagatesEncodeFailureAndDoesNotCacheValue() async throws {
    try await withCoreEngine { engine, _, _, _ in
        let key = coreKey("encode-failure")
        let codec = ThrowingEncodeStringCodec()

        do {
            _ = try await engine.resolve(for: key, codec: codec) {
                "generated"
            }
            Issue.record("Expected encode error to be thrown.")
        } catch CoreEngineTestError.encode {
        }

        do {
            _ = try await engine.resolve(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                "should-not-run"
            }
            Issue.record("Expected encode failure not to cache value.")
        } catch CacheCoreError.cacheMiss {
        }
    }
}

private struct UTF8StringCodec: CacheCodec {
    var identifier = "utf8-string-v1"

    func encode(_ value: String) throws -> Data {
        Data(value.utf8)
    }

    func decode(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
    }
}

private struct ThrowingEncodeStringCodec: CacheCodec {
    var identifier = "throwing-encode-string-v1"

    func encode(_ value: String) throws -> Data {
        throw CoreEngineTestError.encode
    }

    func decode(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
    }
}

private struct ThrowingDecodeStringCodec: CacheCodec {
    var identifier = "throwing-decode-string-v1"

    func encode(_ value: String) throws -> Data {
        Data(value.utf8)
    }

    func decode(_ data: Data) throws -> String {
        throw CoreEngineTestError.decode
    }
}

private enum CoreEngineTestError: Error, Equatable {
    case generator
    case encode
    case decode
}

private actor CallCounter {
    private var value = 0

    var count: Int {
        value
    }

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

private func withCoreEngine<T>(
    now: Date = Date(timeIntervalSince1970: 1_800_000_200),
    _ operation: (CacheCoreEngine, MemoryCacheStore, StorageCacheStore, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaCoreEngineTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let memory = MemoryCacheStore()
    let storage = StorageCacheStore(rootDirectory: rootDirectory, now: { now })
    let engine = CacheCoreEngine(memory: memory, storage: storage, now: { now })

    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    return try await operation(engine, memory, storage, rootDirectory)
}

private func coreKey(_ name: String) -> CacheKey {
    CacheKey(namespace: "core-engine-tests", identity: name)
}

private func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
