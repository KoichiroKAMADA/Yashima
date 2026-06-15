import Foundation
import Testing
import Yashima

@Test func yCacheResolveGeneratesStoresAndReportsMetadata() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("resolve")
        let codec = PublicUTF8StringCodec()

        let generated = try await cache.resolve(for: key, codec: codec) {
            "fresh"
        }
        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted = try await newCache.resolve(for: key, codec: codec) {
            "regenerated"
        }

        #expect(generated.value == "fresh")
        #expect(generated.source == .generated)
        #expect(generated.metadata?.byteCount == 5)
        #expect(generated.metadata?.codecIdentifier == codec.identifier)
        #expect(!generated.wasSharedGeneration)
        #expect(persisted.value == "fresh")
        #expect(persisted.source == .storage)
    }
}

@Test func yCacheValueIfCachedReturnsNilForMissAndPromotesStorageHit() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("value-if-cached")
        let codec = PublicUTF8StringCodec()

        let missing = try await cache.valueIfCached(for: key, codec: codec)
        try await cache.store("stored", for: key, codec: codec)

        let newCache = YCache(storageDirectory: rootDirectory)
        let beforePromotion = try await newCache.peek(for: key, codec: codec)
        let cached = try await newCache.valueIfCached(for: key, codec: codec)
        let afterPromotion = try await newCache.peek(for: key, codec: codec)

        #expect(missing == nil)
        #expect(beforePromotion == nil)
        #expect(cached == "stored")
        #expect(afterPromotion == "stored")
    }
}

@Test func yCacheRefreshBypassesExistingCacheAndUpdatesIt() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("refresh")
        let codec = PublicUTF8StringCodec()

        let first = try await cache.value(for: key, codec: codec) {
            "old"
        }
        let refreshed = try await cache.refresh(for: key, codec: codec) {
            "new"
        }
        let cachedAgain = try await cache.value(for: key, codec: codec) {
            "unused"
        }

        #expect(first == "old")
        #expect(refreshed == "new")
        #expect(cachedAgain == "new")
    }
}

@Test func yCachePeekReadsMemoryOnly() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("peek")
        let codec = PublicUTF8StringCodec()

        try await cache.store("stored", for: key, codec: codec)

        let newCache = YCache(storageDirectory: rootDirectory)
        let memoryMiss = try await newCache.peek(for: key, codec: codec)
        let storageHit = try await newCache.valueIfCached(for: key, codec: codec)
        let memoryHit = try await newCache.peek(for: key, codec: codec)

        #expect(memoryMiss == nil)
        #expect(storageHit == "stored")
        #expect(memoryHit == "stored")
    }
}

@Test func yCacheTypedFacadeUsesTheSameIdentityAsRootAPI() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("typed")
        let codec = PublicUTF8StringCodec()
        let typed = cache.using(codec)

        try await cache.store("root", for: key, codec: codec)
        let typedValue = try await typed.valueIfCached(for: key)

        try await typed.store("typed", for: key)
        let rootValue = try await cache.valueIfCached(for: key, codec: codec)

        #expect(typedValue == "root")
        #expect(rootValue == "typed")
    }
}

@Test func yCacheCoalescesConcurrentPublicRequests() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("single-flight")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        let results = try await withThrowingTaskGroup(of: YCache.Resolved<String>.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await cache.resolve(for: key, codec: codec) {
                        let invocation = await counter.increment()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return "shared-\(invocation)"
                    }
                }
            }

            var resolved: [YCache.Resolved<String>] = []
            for try await result in group {
                resolved.append(result)
            }
            return resolved
        }

        #expect(results.count == 20)
        #expect(results.allSatisfy { $0.value == "shared-1" })
        #expect(results.allSatisfy { $0.source == .generated })
        #expect(results.contains { $0.wasSharedGeneration })
        #expect(await counter.count == 1)
    }
}

@Test func yCachePutInMemoryDoesNotPersistToStorage() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("put-in-memory")
        let codec = PublicUTF8StringCodec()

        try await cache.putInMemory("memory", for: key, codec: codec)

        let memoryHit = try await cache.peek(for: key, codec: codec)
        let newCache = YCache(storageDirectory: rootDirectory)
        let storageMiss = try await newCache.valueIfCached(for: key, codec: codec)

        #expect(memoryHit == "memory")
        #expect(storageMiss == nil)
    }
}

@Test func yCacheStorePersistsValueWithoutRunningGenerator() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("store")
        let codec = PublicUTF8StringCodec()

        try await cache.store("stored", for: key, codec: codec)

        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted = try await newCache.valueIfCached(for: key, codec: codec)

        #expect(persisted == "stored")
    }
}

@Test func yCacheOptionalValueDoesNotCacheNilGeneration() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional")
        let codec = PublicUTF8StringCodec()

        let first = try await cache.optionalValue(for: key, codec: codec) {
            nil
        }
        let second = try await cache.optionalValue(for: key, codec: codec) {
            "later"
        }
        let cached = try await cache.valueIfCached(for: key, codec: codec)

        #expect(first == nil)
        #expect(second == "later")
        #expect(cached == "later")
    }
}

@Test func yCacheCacheOnlyResolveThrowsPublicCacheMiss() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("cache-only")
        let codec = PublicUTF8StringCodec()

        do {
            _ = try await cache.value(
                for: key,
                codec: codec,
                options: .init(lookupPolicy: .cacheOnly)
            ) {
                "should-not-run"
            }
            Issue.record("Expected cache-only miss to throw.")
        } catch YCache.Error.cacheMiss {
        }
    }
}

private struct PublicUTF8StringCodec: CacheCodec {
    var identifier = "public-utf8-string-v1"

    func encode(_ value: String) throws -> Data {
        Data(value.utf8)
    }

    func decode(_ data: Data) throws -> String {
        String(decoding: data, as: UTF8.self)
    }
}

private actor YCacheCallCounter {
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

private func withYCache<T>(
    _ operation: (YCache, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicAPITests-\(UUID().uuidString)",
        isDirectory: true
    )
    let cache = YCache(storageDirectory: rootDirectory)

    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    return try await operation(cache, rootDirectory)
}

private func yCacheKey(_ name: String) -> CacheKey {
    CacheKey(namespace: "public-api-tests", identity: name)
}
