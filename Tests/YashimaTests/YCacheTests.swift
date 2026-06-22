import Foundation
import Testing
import Yashima

@Test func yCacheConfigurationUsesFiniteDefaultBudgets() {
    let rootDirectory = FileManager.default.temporaryDirectory
    let configuration = YCache.Configuration(storageDirectory: rootDirectory)
    let cache = YCache(storageDirectory: rootDirectory)

    #expect(YCache.Configuration.defaultMemoryMaximumCost == 64 * 1024 * 1024)
    #expect(YCache.Configuration.defaultMemoryMaximumEntryCount == nil)
    #expect(YCache.Configuration.defaultStorageMaximumByteCount == 128 * 1024 * 1024)
    #expect(configuration.memoryMaximumCost == YCache.Configuration.defaultMemoryMaximumCost)
    #expect(configuration.memoryMaximumEntryCount == nil)
    #expect(configuration.storageMaximumByteCount == YCache.Configuration.defaultStorageMaximumByteCount)
    #expect(cache.configuration == configuration)
}

@Test func yCacheConfigurationAllowsCustomAndExplicitUnboundedBudgets() {
    let rootDirectory = FileManager.default.temporaryDirectory

    let custom = YCache.Configuration(
        storageDirectory: rootDirectory,
        memoryMaximumCost: 12,
        memoryMaximumEntryCount: 34,
        storageMaximumByteCount: 56
    )
    let unbounded = YCache.Configuration(
        storageDirectory: rootDirectory,
        memoryMaximumCost: nil,
        memoryMaximumEntryCount: nil,
        storageMaximumByteCount: nil
    )

    #expect(custom.memoryMaximumCost == 12)
    #expect(custom.memoryMaximumEntryCount == 34)
    #expect(custom.storageMaximumByteCount == 56)
    #expect(unbounded.memoryMaximumCost == nil)
    #expect(unbounded.memoryMaximumEntryCount == nil)
    #expect(unbounded.storageMaximumByteCount == nil)
}

@Test func yCacheOptionsExposeSingleFlightPolicy() {
    let defaultOptions = YCache.Options()
    let uiLifecycleOptions = YCache.Options(singleFlightPolicy: .cancelWhenNoWaiters)
    let uiLifecyclePreset = YCache.Options.uiLifecycle
    let disabledOptions = YCache.Options(singleFlightPolicy: .disabled)

    #expect(defaultOptions.singleFlightPolicy == .share)
    #expect(uiLifecycleOptions.singleFlightPolicy == .cancelWhenNoWaiters)
    #expect(uiLifecyclePreset.writeFailurePolicy == .bestEffort)
    #expect(uiLifecyclePreset.singleFlightPolicy == .cancelWhenNoWaiters)
    #expect(disabledOptions.singleFlightPolicy == .disabled)
}

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

@Test func yCacheRemoveDeletesMemoryAndStorageEntry() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("remove")
        let codec = PublicUTF8StringCodec()

        try await cache.store("stored", for: key, codec: codec)

        let firstRemoval = try await cache.remove(for: key, codec: codec)
        let secondRemoval = try await cache.remove(for: key, codec: codec)
        let memoryMiss = try await cache.peek(for: key, codec: codec)
        let storageMiss = try await YCache(storageDirectory: rootDirectory)
            .valueIfCached(for: key, codec: codec)

        #expect(firstRemoval)
        #expect(!secondRemoval)
        #expect(memoryMiss == nil)
        #expect(storageMiss == nil)
    }
}

@Test func yCacheRemoveAllDeletesEveryEntryPreservesUnmanagedFilesAndAllowsRegeneration() async throws {
    try await withYCache { cache, rootDirectory in
        let codec = PublicUTF8StringCodec()
        let first = yCacheKey("remove-all-first")
        let second = yCacheKey("remove-all-second")
        let unmanagedFile = rootDirectory.appendingPathComponent("unmanaged.txt")

        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: unmanagedFile)
        try await cache.store("first", for: first, codec: codec)
        try await cache.store("second", for: second, codec: codec)
        try await cache.removeAll()

        let firstMiss = try await cache.valueIfCached(for: first, codec: codec)
        let secondMiss = try await cache.valueIfCached(for: second, codec: codec)
        let regenerated = try await cache.value(for: first, codec: codec) {
            "regenerated"
        }

        #expect(firstMiss == nil)
        #expect(secondMiss == nil)
        #expect(regenerated == "regenerated")
        #expect(FileManager.default.fileExists(atPath: unmanagedFile.path))
    }
}

@Test func yCacheRemoveAllInNamespaceOnlyDeletesMatchingNamespace() async throws {
    try await withYCache { cache, rootDirectory in
        let codec = PublicUTF8StringCodec()
        let keptKey = CacheKey(namespace: "kept-namespace", identity: "value")
        let removedKey = CacheKey(namespace: "removed-namespace", identity: "value")

        try await cache.store("kept", for: keptKey, codec: codec)
        try await cache.store("removed", for: removedKey, codec: codec)
        try await cache.removeAll(in: "removed-namespace")

        let sameCacheRemoved = try await cache.valueIfCached(for: removedKey, codec: codec)
        let sameCacheKept = try await cache.valueIfCached(for: keptKey, codec: codec)
        let newCache = YCache(storageDirectory: rootDirectory)
        let storageRemoved = try await newCache.valueIfCached(for: removedKey, codec: codec)
        let storageKept = try await newCache.valueIfCached(for: keptKey, codec: codec)

        #expect(sameCacheRemoved == nil)
        #expect(sameCacheKept == "kept")
        #expect(storageRemoved == nil)
        #expect(storageKept == "kept")
    }
}

@Test func yCacheContainsAndMetadataDoNotDecodePayload() async throws {
    try await withYCache { cache, rootDirectory in
        let key = yCacheKey("metadata-with-throwing-decode")
        let codec = PublicThrowingDecodeStringCodec()

        try await cache.store("stored", for: key, codec: codec)

        let newCache = YCache(storageDirectory: rootDirectory)
        let contains = try await newCache.contains(for: key, codec: codec)
        let metadata = try await newCache.metadata(for: key, codec: codec)
        let decoded = try await newCache.valueIfCached(for: key, codec: codec)

        #expect(contains)
        #expect(metadata?.byteCount == 6)
        #expect(metadata?.codecIdentifier == codec.identifier)
        #expect(decoded == nil)
    }
}

@Test func yCacheTypedFacadeExposesLifecycleOperations() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("typed-lifecycle")
        let typed = cache.using(PublicUTF8StringCodec())

        try await typed.store("stored", for: key)

        let containsBeforeRemoval = try await typed.contains(for: key)
        let metadataBeforeRemoval = try await typed.metadata(for: key)
        let removed = try await typed.remove(for: key)
        let containsAfterRemoval = try await typed.contains(for: key)

        #expect(containsBeforeRemoval)
        #expect(metadataBeforeRemoval?.byteCount == 6)
        #expect(removed)
        #expect(!containsAfterRemoval)
    }
}

@Test func yCacheStorageUsageReportsEntriesBytesAndMaximum() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicStorageUsageTests-\(UUID().uuidString)",
        isDirectory: true
    )
    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    let cache = YCache(storageDirectory: rootDirectory, storageMaximumByteCount: 7)
    let codec = PublicUTF8StringCodec()

    try await cache.store("12345", for: yCacheKey("usage-first"), codec: codec)
    try await cache.store("abcde", for: yCacheKey("usage-second"), codec: codec)

    let usage = try await cache.storageUsage()

    #expect(usage.maximumByteCount == 7)
    #expect(usage.byteCount <= 7)
    #expect(usage.entryCount == 1)
}

@Test func yCacheBestEffortWriteFailureReturnsGeneratedValueAndCachesInMemoryOnly() async throws {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicWriteFailureTests-\(UUID().uuidString)",
        isDirectory: false
    )
    try Data("not-a-directory".utf8).write(to: rootURL)
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }

    let cache = YCache(storageDirectory: rootURL)
    let key = yCacheKey("best-effort-write-failure")
    let codec = PublicUTF8StringCodec()

    let resolved = try await cache.resolve(
        for: key,
        codec: codec,
        options: .init(writeFailurePolicy: .bestEffort)
    ) {
        "memory"
    }
    let memoryHit = try await cache.peek(for: key, codec: codec)
    let persisted = try await YCache(storageDirectory: rootURL).valueIfCached(for: key, codec: codec)

    #expect(resolved.value == "memory")
    #expect(resolved.source == .generated)
    #expect(resolved.metadata?.byteCount == 6)
    #expect(memoryHit == "memory")
    #expect(persisted == nil)
}

@Test func yCacheThrowingWriteFailureDoesNotCacheIncompleteEntry() async throws {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicThrowingWriteFailureTests-\(UUID().uuidString)",
        isDirectory: false
    )
    try Data("not-a-directory".utf8).write(to: rootURL)
    defer {
        try? FileManager.default.removeItem(at: rootURL)
    }

    let cache = YCache(storageDirectory: rootURL)
    let key = yCacheKey("throwing-write-failure")
    let codec = PublicUTF8StringCodec()

    do {
        _ = try await cache.value(for: key, codec: codec) {
            "should-not-cache"
        }
        Issue.record("Expected storage write failure to throw.")
    } catch {
    }

    let memoryMiss = try await cache.peek(for: key, codec: codec)
    let persisted = try await YCache(storageDirectory: rootURL).valueIfCached(for: key, codec: codec)

    #expect(memoryMiss == nil)
    #expect(persisted == nil)
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

@Test func yCacheOptionalValueCoalescesConcurrentMisses() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-single-flight")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        let values = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await cache.optionalValue(for: key, codec: codec) {
                        let invocation = await counter.increment()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return "shared-\(invocation)"
                    }
                }
            }

            var values: [String?] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        let cached = try await cache.valueIfCached(for: key, codec: codec)

        #expect(values.count == 20)
        #expect(values.allSatisfy { $0 == "shared-1" })
        #expect(cached == "shared-1")
        #expect(await counter.count == 1)
    }
}

@Test func yCacheOptionalValueCoalescesConcurrentNilAndDoesNotCacheIt() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-single-flight-nil")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        let values = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await cache.optionalValue(for: key, codec: codec) {
                        _ = await counter.increment()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return nil
                    }
                }
            }

            var values: [String?] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        let cached = try await cache.valueIfCached(for: key, codec: codec)

        #expect(values.count == 20)
        #expect(values.allSatisfy { $0 == nil })
        #expect(cached == nil)
        #expect(await counter.count == 1)
    }
}

@Test func yCacheOptionalValueSequentialNilMissesRerunGenerator() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-sequential-nil")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        let first = try await cache.optionalValue(for: key, codec: codec) {
            _ = await counter.increment()
            return nil
        }
        let second = try await cache.optionalValue(for: key, codec: codec) {
            _ = await counter.increment()
            return nil
        }
        let cached = try await cache.valueIfCached(for: key, codec: codec)

        #expect(first == nil)
        #expect(second == nil)
        #expect(cached == nil)
        #expect(await counter.count == 2)
    }
}

@Test func yCacheOptionalValuePropagatesGeneratorCacheMiss() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-propagates-cache-miss")
        let codec = PublicUTF8StringCodec()

        do {
            let _: String? = try await cache.optionalValue(for: key, codec: codec) {
                throw YCache.Error.cacheMiss
            }
            Issue.record("Expected generator cacheMiss to propagate.")
        } catch YCache.Error.cacheMiss {
        } catch {
            Issue.record("Expected cacheMiss, got \(error).")
        }

        let cached = try await cache.valueIfCached(for: key, codec: codec)
        #expect(cached == nil)
    }
}

@Test func yCacheOptionalValueCacheOnlyDoesNotGenerate() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-cache-only")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        let missing = try await cache.optionalValue(
            for: key,
            codec: codec,
            options: .init(lookupPolicy: .cacheOnly)
        ) {
            _ = await counter.increment()
            return "should-not-run"
        }

        #expect(missing == nil)
        #expect(await counter.count == 0)
    }
}

@Test func yCacheOptionalValueRefreshBypassesCacheAndStoresReturnedValue() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-refresh")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()

        try await cache.store("old", for: key, codec: codec)
        let refreshed = try await cache.optionalValue(
            for: key,
            codec: codec,
            options: .init(lookupPolicy: .refresh)
        ) {
            let invocation = await counter.increment()
            return "new-\(invocation)"
        }
        let cached = try await cache.valueIfCached(for: key, codec: codec)

        #expect(refreshed == "new-1")
        #expect(cached == "new-1")
        #expect(await counter.count == 1)
    }
}

@Test func yCacheOptionalValueDisabledSingleFlightRunsIndependentGenerators() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-disabled")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()
        let gate = YCacheAsyncGate()
        let taskCount = 6
        let options = YCache.Options(
            lookupPolicy: .refresh,
            singleFlightPolicy: .disabled
        )

        let values = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    try await cache.optionalValue(for: key, codec: codec, options: options) {
                        let invocation = await counter.increment()
                        if invocation == taskCount {
                            await gate.open()
                        }
                        await gate.wait()
                        return "generated-\(invocation)"
                    }
                }
            }

            var values: [String?] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        #expect(values.count == taskCount)
        #expect(Set(values.compactMap { $0 }).count == taskCount)
        #expect(await counter.count == taskCount)
    }
}

@Test func yCacheOptionalValueCancellationDoesNotCacheGeneratedValue() async throws {
    try await withYCache { cache, _ in
        let key = yCacheKey("optional-cancelled")
        let codec = PublicUTF8StringCodec()
        let counter = YCacheCallCounter()
        let probe = YCacheCancellationProbe()

        let first = Task {
            try await cache.optionalValue(
                for: key,
                codec: codec,
                options: .uiLifecycle
            ) {
                _ = await counter.increment()
                do {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                } catch is CancellationError {
                    await probe.markObserved()
                    throw CancellationError()
                }
            }
        }
        await counter.waitUntil(1)

        let second = Task {
            try await cache.optionalValue(
                for: key,
                codec: codec,
                options: .uiLifecycle
            ) {
                _ = await counter.increment()
                do {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                } catch is CancellationError {
                    await probe.markObserved()
                    throw CancellationError()
                }
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        second.cancel()

        await expectCancellation(from: first)
        await expectCancellation(from: second)
        try await probe.waitUntilObserved()

        let cached = try await cache.valueIfCached(for: key, codec: codec)
        #expect(cached == nil)
        #expect(await counter.count == 1)
    }
}

@Test func yCacheDefaultMemoryHasNoEntryCountLimit() async throws {
    try await withYCache { cache, _ in
        let codec = DataCodec()
        let entryCount = 150

        for index in 0..<entryCount {
            try await cache.store(
                Data([UInt8(index % 256)]),
                for: yCacheKey("small-\(index)"),
                codec: codec
            )
        }

        var memoryHitCount = 0
        for index in 0..<entryCount {
            if try await cache.peek(for: yCacheKey("small-\(index)"), codec: codec) != nil {
                memoryHitCount += 1
            }
        }

        #expect(memoryHitCount == entryCount)
    }
}

@Test func yCacheSmallMemoryBudgetEvictsLRUAndKeepsStorageReadable() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicAPITests-\(UUID().uuidString)",
        isDirectory: true
    )
    let cache = YCache(
        storageDirectory: rootDirectory,
        memoryMaximumCost: 10,
        storageMaximumByteCount: nil
    )
    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    let first = yCacheKey("lru-first")
    let second = yCacheKey("lru-second")
    let third = yCacheKey("lru-third")
    let codec = DataCodec()

    try await cache.store(Data(repeating: 1, count: 4), for: first, codec: codec)
    try await cache.store(Data(repeating: 2, count: 4), for: second, codec: codec)
    _ = try await cache.peek(for: first, codec: codec)
    try await cache.store(Data(repeating: 3, count: 4), for: third, codec: codec)

    let firstMemory = try await cache.peek(for: first, codec: codec)
    let secondMemory = try await cache.peek(for: second, codec: codec)
    let thirdMemory = try await cache.peek(for: third, codec: codec)
    let secondStorage = try await cache.resolve(for: second, codec: codec) {
        throw PublicCodecTestError.unexpectedGeneration
    }

    #expect(firstMemory == Data(repeating: 1, count: 4))
    #expect(secondMemory == nil)
    #expect(thirdMemory == Data(repeating: 3, count: 4))
    #expect(secondStorage.source == .storage)
    #expect(secondStorage.value == Data(repeating: 2, count: 4))
}

@Test func yCacheEntryLargerThanMemoryBudgetDoesNotStayInMemoryButPersistsToStorage() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaPublicAPITests-\(UUID().uuidString)",
        isDirectory: true
    )
    let cache = YCache(
        storageDirectory: rootDirectory,
        memoryMaximumCost: 5,
        storageMaximumByteCount: nil
    )
    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    let key = yCacheKey("oversized-memory")
    let value = Data(repeating: 9, count: 6)
    let codec = DataCodec()

    try await cache.store(value, for: key, codec: codec)
    let memoryMiss = try await cache.peek(for: key, codec: codec)
    let storageHit = try await cache.resolve(for: key, codec: codec) {
        throw PublicCodecTestError.unexpectedGeneration
    }
    let stillMemoryMiss = try await cache.peek(for: key, codec: codec)

    #expect(memoryMiss == nil)
    #expect(storageHit.source == .storage)
    #expect(storageHit.value == value)
    #expect(stillMemoryMiss == nil)
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

private struct PublicThrowingDecodeStringCodec: CacheCodec {
    var identifier = "public-throwing-decode-string-v1"

    func encode(_ value: String) throws -> Data {
        Data(value.utf8)
    }

    func decode(_ data: Data) throws -> String {
        throw PublicCodecTestError.decode
    }
}

private enum PublicCodecTestError: Error {
    case decode
    case timeout
    case unexpectedGeneration
}

private actor YCacheCallCounter {
    private var value = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var count: Int {
        value
    }

    @discardableResult
    func increment() -> Int {
        value += 1
        resumeSatisfiedWaiters()
        return value
    }

    func waitUntil(_ target: Int) async {
        guard value < target else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append((target: target, continuation: continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if value >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

private actor YCacheAsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else {
            return
        }

        isOpen = true
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor YCacheCancellationProbe {
    private var observed = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func markObserved() {
        guard !observed else {
            return
        }

        observed = true
        let continuations = continuations
        self.continuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func waitUntilObserved() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.wait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw PublicCodecTestError.timeout
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func wait() async {
        guard !observed else {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private func expectCancellation<T>(
    from task: Task<T, any Error>
) async {
    do {
        _ = try await task.value
        Issue.record("Expected task to throw CancellationError.")
    } catch is CancellationError {
    } catch {
        Issue.record("Expected CancellationError, got \(error).")
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
