import Foundation
import Yashima

public enum StressScenarios {
    public static let all: [StressScenario] = [
        StressScenario(name: "SingleFlightBurst", run: singleFlightBurst),
        StressScenario(name: "ConcurrentArtifactMix", run: concurrentArtifactMix),
        StressScenario(name: "LifecycleUnderLoad", run: lifecycleUnderLoad),
        StressScenario(name: "StorageLimitTrim", run: storageLimitTrim),
        StressScenario(name: "ExactCapacityReplacement", run: exactCapacityReplacement),
        StressScenario(name: "ConcurrentQuotaPressure", run: concurrentQuotaPressure),
        StressScenario(name: "MemoryLimitPressure", run: memoryLimitPressure),
        StressScenario(name: "OversizedEntryPressure", run: oversizedEntryPressure),
        StressScenario(name: "CorruptionRecovery", run: corruptionRecovery),
        StressScenario(name: "CancellationChurn", run: cancellationChurn),
        StressScenario(name: "CancellationAwareSingleFlight", run: cancellationAwareSingleFlight),
    ]

    private static func singleFlightBurst(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let cache = YCache(storageDirectory: context.rootDirectory)
        let key = CacheKey(namespace: "stress-single-flight", identity: "burst")
        let payload = DeterministicPayload.data(
            seed: context.seed,
            index: 0,
            byteCount: min(8 * 1024, context.profile.maximumPayloadByteCount)
        )
        let counter = StressCounter()

        let results = try await withThrowingTaskGroup(of: YCache.Resolved<Data>.self) { group in
            for _ in 0..<context.profile.singleFlightFanout {
                group.addTask {
                    try await cache.resolve(for: key, codec: DataCodec()) {
                        _ = await counter.increment()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        return payload
                    }
                }
            }

            var values: [YCache.Resolved<Data>] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        try require(results.count == context.profile.singleFlightFanout, "Single-flight result count mismatch.")
        try require(results.allSatisfy { $0.value == payload }, "Single-flight returned inconsistent values.")
        try require(results.allSatisfy { $0.source == .generated }, "Single-flight should resolve as generated for all waiters.")
        try require(results.contains { $0.wasSharedGeneration }, "Single-flight did not report a shared generation.")
        let singleFlightGeneratorCount = await counter.value
        try require(singleFlightGeneratorCount == 1, "Single-flight generator ran more than once.")

        let coldCache = YCache(storageDirectory: context.rootDirectory)
        let persisted = try await coldCache.resolve(for: key, codec: DataCodec()) {
            throw StressFailure("Single-flight result was not persisted.")
        }
        try require(persisted.source == .storage, "Single-flight result was not read from storage.")
        try require(persisted.value == payload, "Stored single-flight payload changed.")

        return StressScenarioSummary(
            operations: context.profile.singleFlightFanout + 1,
            generatedCount: results.count,
            storageHitCount: 1
        )
    }

    private static func concurrentArtifactMix(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let cache = YCache(storageDirectory: context.rootDirectory)
        let metrics = StressMetrics()
        let indexes = Array(0..<context.profile.keyCount)

        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let key = artifactKey(index)
            switch artifactKind(for: index) {
            case .data:
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                    expected
                }
                try require(resolved.value == expected, "Data artifact changed during generation.")
                await metrics.record(resolved.source)
            case .codableJSON:
                let expected = DeterministicPayload.codableArtifact(seed: context.seed, index: index, profile: context.profile)
                let codec = CodableCodec<StressCodableArtifact>(format: .json)
                let resolved = try await cache.resolve(for: key, codec: codec) {
                    expected
                }
                try require(resolved.value == expected, "JSON artifact changed during generation.")
                await metrics.record(resolved.source)
            case .codablePropertyList:
                let expected = DeterministicPayload.codableArtifact(seed: context.seed, index: index, profile: context.profile)
                let codec = CodableCodec<StressCodableArtifact>(format: .propertyList)
                let resolved = try await cache.resolve(for: key, codec: codec) {
                    expected
                }
                try require(resolved.value == expected, "Property list artifact changed during generation.")
                await metrics.record(resolved.source)
            case .jpeg:
                #if canImport(UIKit) || canImport(AppKit)
                let expectedSize = imageSize(for: index)
                _ = try await cache.jpeg(for: key, quality: 0.85) {
                    DeterministicImage.make(
                        width: expectedSize.width,
                        height: expectedSize.height,
                        seed: context.seed,
                        index: index
                    )
                }
                await metrics.record(.generated)
                #else
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                    expected
                }
                try require(resolved.value == expected, "Fallback artifact changed during generation.")
                await metrics.record(resolved.source)
                #endif
            case .png:
                #if canImport(UIKit) || canImport(AppKit)
                let expectedSize = imageSize(for: index)
                _ = try await cache.png(for: key) {
                    DeterministicImage.make(
                        width: expectedSize.width,
                        height: expectedSize.height,
                        seed: context.seed,
                        index: index
                    )
                }
                await metrics.record(.generated)
                #else
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                    expected
                }
                try require(resolved.value == expected, "Fallback artifact changed during generation.")
                await metrics.record(resolved.source)
                #endif
            }
        }

        let coldCache = YCache(storageDirectory: context.rootDirectory)
        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let key = artifactKey(index)
            switch artifactKind(for: index) {
            case .data:
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await coldCache.resolve(for: key, codec: DataCodec()) {
                    throw StressFailure("Data artifact was not stored.")
                }
                try require(resolved.source == .storage, "Data artifact did not come from storage.")
                try require(resolved.value == expected, "Stored data artifact changed.")
                await metrics.record(resolved.source)
            case .codableJSON:
                let expected = DeterministicPayload.codableArtifact(seed: context.seed, index: index, profile: context.profile)
                let codec = CodableCodec<StressCodableArtifact>(format: .json)
                let resolved = try await coldCache.resolve(for: key, codec: codec) {
                    throw StressFailure("JSON artifact was not stored.")
                }
                try require(resolved.source == .storage, "JSON artifact did not come from storage.")
                try require(resolved.value == expected, "Stored JSON artifact changed.")
                await metrics.record(resolved.source)
            case .codablePropertyList:
                let expected = DeterministicPayload.codableArtifact(seed: context.seed, index: index, profile: context.profile)
                let codec = CodableCodec<StressCodableArtifact>(format: .propertyList)
                let resolved = try await coldCache.resolve(for: key, codec: codec) {
                    throw StressFailure("Property list artifact was not stored.")
                }
                try require(resolved.source == .storage, "Property list artifact did not come from storage.")
                try require(resolved.value == expected, "Stored property list artifact changed.")
                await metrics.record(resolved.source)
            case .jpeg:
                #if canImport(UIKit) || canImport(AppKit)
                let expectedSize = imageSize(for: index)
                let resolved = try await coldCache.resolve(for: key, codec: ImageCodec.jpeg(quality: 0.85)) {
                    throw StressFailure("JPEG artifact was not stored.")
                }
                try require(resolved.source == .storage, "JPEG artifact did not come from storage.")
                try require(DeterministicImage.size(resolved.value) == expectedSize, "Stored JPEG dimensions changed.")
                await metrics.record(resolved.source)
                #else
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await coldCache.resolve(for: key, codec: DataCodec()) {
                    throw StressFailure("Fallback artifact was not stored.")
                }
                try require(resolved.value == expected, "Stored fallback artifact changed.")
                await metrics.record(resolved.source)
                #endif
            case .png:
                #if canImport(UIKit) || canImport(AppKit)
                let expectedSize = imageSize(for: index)
                let resolved = try await coldCache.resolve(for: key, codec: ImageCodec.png) {
                    throw StressFailure("PNG artifact was not stored.")
                }
                try require(resolved.source == .storage, "PNG artifact did not come from storage.")
                try require(DeterministicImage.size(resolved.value) == expectedSize, "Stored PNG dimensions changed.")
                await metrics.record(resolved.source)
                #else
                let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
                let resolved = try await coldCache.resolve(for: key, codec: DataCodec()) {
                    throw StressFailure("Fallback artifact was not stored.")
                }
                try require(resolved.value == expected, "Stored fallback artifact changed.")
                await metrics.record(resolved.source)
                #endif
            }
        }

        return await metrics.summary(operations: context.profile.keyCount * 2)
    }

    private static func lifecycleUnderLoad(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let cache = YCache(storageDirectory: context.rootDirectory)
        let metrics = StressMetrics()
        let indexes = Array(0..<context.profile.keyCount)
        let removedNamespace = "stress-lifecycle-removed"
        let activeNamespace = "stress-lifecycle-active"

        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let namespace = index.isMultiple(of: 5) ? removedNamespace : activeNamespace
            let key = CacheKey(namespace: namespace, identity: "entry-\(index)")
            let value = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)

            switch index % 6 {
            case 0:
                let resolved = try await cache.resolve(for: key, codec: DataCodec()) { value }
                try require(resolved.value == value, "Lifecycle value changed.")
                let contains = try await cache.contains(for: key, codec: DataCodec())
                let metadata = try await cache.metadata(for: key, codec: DataCodec())
                try require(contains, "Lifecycle contains returned false.")
                try require(metadata != nil, "Lifecycle metadata was missing.")
                await metrics.record(resolved.source, operations: 3)
            case 1:
                try await cache.store(value, for: key, codec: DataCodec())
                let cached = try await cache.valueIfCached(for: key, codec: DataCodec())
                try require(cached == value, "Stored lifecycle value was not cached.")
                await metrics.record(.generated, operations: 2)
            case 2:
                _ = try await cache.value(for: key, codec: DataCodec()) { value }
                let refreshedValue = DeterministicPayload.data(
                    seed: context.seed,
                    index: index + context.profile.keyCount,
                    profile: context.profile
                )
                let refreshed = try await cache.refresh(for: key, codec: DataCodec()) {
                    refreshedValue
                }
                let cached = try await cache.valueIfCached(for: key, codec: DataCodec())
                try require(refreshed == refreshedValue, "Lifecycle refresh returned the wrong value.")
                try require(cached == refreshedValue, "Lifecycle refresh was not cached.")
                await metrics.record(.generated, operations: 3)
            case 3:
                _ = try await cache.value(for: key, codec: DataCodec()) { value }
                let removed = try await cache.remove(for: key, codec: DataCodec())
                let missing = try await cache.valueIfCached(for: key, codec: DataCodec())
                let regenerated = try await cache.resolve(for: key, codec: DataCodec()) { value }
                try require(removed, "Lifecycle remove returned false.")
                try require(missing == nil, "Removed lifecycle value remained cached.")
                try require(regenerated.value == value, "Lifecycle regeneration changed the value.")
                await metrics.record(regenerated.source, operations: 4, removed: 1, regenerated: 1)
            default:
                let resolved = try await cache.resolve(for: key, codec: DataCodec()) { value }
                let cached = try await cache.valueIfCached(for: key, codec: DataCodec())
                try require(resolved.value == value, "Lifecycle generated value changed.")
                try require(cached == value, "Lifecycle cached value changed.")
                await metrics.record(resolved.source, operations: 2)
            }
        }

        try await cache.removeAll(in: removedNamespace)
        await metrics.recordOperation(removed: indexes.filter { $0.isMultiple(of: 5) }.count)

        for index in indexes where index.isMultiple(of: 5) {
            let key = CacheKey(namespace: removedNamespace, identity: "entry-\(index)")
            let cached = try await cache.valueIfCached(for: key, codec: DataCodec())
            try require(cached == nil, "Namespace removal left an entry behind.")
        }

        let activeSample = indexes.filter { !$0.isMultiple(of: 5) }.prefix(20)
        for index in activeSample {
            let key = CacheKey(namespace: activeNamespace, identity: "entry-\(index)")
            let contains = try await cache.contains(for: key, codec: DataCodec())
            try require(contains, "Namespace removal removed an active entry.")
        }

        return await metrics.summary(additionalOperations: indexes.filter { $0.isMultiple(of: 5) }.count + activeSample.count)
    }

    private static func storageLimitTrim(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let entryCount = min(context.profile.keyCount, max(80, context.profile.concurrency * 8))
        let maximumByteCount = max(context.profile.maximumPayloadByteCount * 4, 64 * 1024)
        let cache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        )
        let indexes = Array(0..<entryCount)
        let metrics = StressMetrics()

        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let key = trimKey(index)
            let data = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
            let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                data
            }
            try require(resolved.value == data, "Trim scenario generated a changed payload.")
            await metrics.record(resolved.source)
        }

        let usage = try await cache.storageUsage()
        try require(usage.maximumByteCount == maximumByteCount, "Storage usage did not report the configured maximum.")
        try require(usage.byteCount <= maximumByteCount, "Storage usage exceeded the configured maximum.")
        try require(usage.entryCount > 0, "Storage trim removed every entry.")

        let coldCache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        )
        var cachedIndexes: Set<Int> = []
        var storageHitCount = 0

        for index in indexes.reversed() {
            let key = trimKey(index)
            let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
            if let cached = try await coldCache.valueIfCached(for: key, codec: DataCodec()) {
                try require(cached == expected, "Trim scenario returned changed storage data.")
                cachedIndexes.insert(index)
                storageHitCount += 1
            }
        }
        try require(storageHitCount > 0, "Storage trim left no readable entries.")

        var regeneratedCount = 0
        for index in indexes where !cachedIndexes.contains(index) {
            let key = trimKey(index)
            let expected = DeterministicPayload.data(seed: context.seed, index: index, profile: context.profile)
            let regenerated = try await coldCache.resolve(for: key, codec: DataCodec()) {
                expected
            }
            try require(regenerated.value == expected, "Trim scenario regeneration changed data.")
            try require(regenerated.source == .generated, "Trim scenario miss did not regenerate.")
            regeneratedCount += 1
        }

        let finalUsage = try await coldCache.storageUsage()
        try require(finalUsage.byteCount <= maximumByteCount, "Regeneration after trim exceeded the configured maximum.")

        await metrics.recordOperation(
            operations: entryCount + indexes.count + regeneratedCount + 2,
            storage: storageHitCount,
            regenerated: regeneratedCount
        )
        return await metrics.summary()
    }

    private static func exactCapacityReplacement(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let payloadSize = quotaPayloadSize(for: context.profile)
        let cache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: payloadSize
        )
        let writeCount = min(context.profile.keyCount, max(12, context.profile.concurrency))

        for index in 0..<writeCount {
            let key = quotaKey("exact", index)
            let expected = DeterministicPayload.data(
                seed: context.seed,
                index: index,
                byteCount: payloadSize
            )
            let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                expected
            }
            try require(resolved.value == expected, "Exact-capacity write returned changed data.")

            let usage = try await cache.storageUsage()
            try require(usage.byteCount == payloadSize, "Exact-capacity usage should equal one payload.")
            try require(usage.entryCount == 1, "Exact-capacity storage should keep exactly one entry.")

            let coldCache = YCache(
                storageDirectory: context.rootDirectory,
                storageMaximumByteCount: payloadSize
            )
            let latest = try await coldCache.resolve(for: key, codec: DataCodec()) {
                throw StressFailure("Newest exact-capacity entry was not stored.")
            }
            try require(latest.source == .storage, "Newest exact-capacity entry was not read from storage.")
            try require(latest.value == expected, "Newest exact-capacity entry changed on disk.")

            if index > 0 {
                let previousKey = quotaKey("exact", index - 1)
                let previous = try await YCache(
                    storageDirectory: context.rootDirectory,
                    storageMaximumByteCount: payloadSize
                ).valueIfCached(for: previousKey, codec: DataCodec())
                try require(previous == nil, "Previous exact-capacity entry was not trimmed.")
            }
        }

        let finalUsage = try await cache.storageUsage()
        try require(finalUsage.byteCount == payloadSize, "Final exact-capacity usage drifted.")
        let temporaryFileCount = try managedFileCount(in: context.rootDirectory, suffix: ".tmp")
        try require(temporaryFileCount == 0, "Temporary files were left behind.")

        return StressScenarioSummary(
            operations: writeCount * 5,
            generatedCount: writeCount,
            storageHitCount: writeCount,
            removedCount: max(0, writeCount - 1)
        )
    }

    private static func concurrentQuotaPressure(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let payloadSize = quotaPayloadSize(for: context.profile)
        let retainedCapacity = 3
        let maximumByteCount = payloadSize * retainedCapacity
        let writeCount = min(context.profile.keyCount, max(context.profile.concurrency * 8, 96))
        let cache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        )
        let indexes = Array(0..<writeCount)
        let metrics = StressMetrics()

        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let key = quotaKey("concurrent", index)
            let expected = DeterministicPayload.data(
                seed: context.seed,
                index: index,
                byteCount: payloadSize
            )
            let resolved = try await cache.refresh(for: key, codec: DataCodec()) {
                expected
            }
            try require(resolved == expected, "Concurrent quota write returned changed data.")
            await metrics.recordOperation(generated: 1)
        }

        let usage = try await cache.storageUsage()
        try require(usage.maximumByteCount == maximumByteCount, "Concurrent quota maximum was not reported.")
        try require(usage.byteCount <= maximumByteCount, "Concurrent quota writes exceeded the byte limit.")
        try require(usage.entryCount > 0, "Concurrent quota writes left no stored entries.")
        try require(usage.entryCount <= retainedCapacity, "Concurrent quota retained too many entries.")
        let temporaryFileCount = try managedFileCount(in: context.rootDirectory, suffix: ".tmp")
        try require(temporaryFileCount == 0, "Concurrent quota left temporary files behind.")

        let coldCache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        )
        var storageHitCount = 0
        var missCount = 0
        for index in indexes {
            let key = quotaKey("concurrent", index)
            let expected = DeterministicPayload.data(
                seed: context.seed,
                index: index,
                byteCount: payloadSize
            )
            if let cached = try await coldCache.valueIfCached(for: key, codec: DataCodec()) {
                try require(cached == expected, "Concurrent quota retained changed data.")
                storageHitCount += 1
            } else {
                missCount += 1
            }
        }
        try require(storageHitCount > 0, "Concurrent quota retained no readable entries.")
        try require(missCount > 0, "Concurrent quota did not trim any older entries.")

        let sentinelKey = quotaKey("concurrent-sentinel", 0)
        let sentinel = DeterministicPayload.data(
            seed: context.seed,
            index: writeCount + 1,
            byteCount: payloadSize
        )
        let sentinelValue = try await coldCache.refresh(for: sentinelKey, codec: DataCodec()) {
            sentinel
        }
        try require(sentinelValue == sentinel, "Post-pressure sentinel write changed data.")
        let sentinelUsage = try await coldCache.storageUsage()
        try require(sentinelUsage.byteCount <= maximumByteCount, "Post-pressure sentinel exceeded the byte limit.")
        let sentinelResolved = try await YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        ).resolve(for: sentinelKey, codec: DataCodec()) {
            throw StressFailure("Post-pressure sentinel was not persisted.")
        }
        try require(sentinelResolved.source == .storage, "Post-pressure sentinel did not survive as storage.")
        try require(sentinelResolved.value == sentinel, "Post-pressure sentinel changed on disk.")

        await metrics.recordOperation(
            operations: indexes.count + 4,
            storage: storageHitCount + 1,
            removed: missCount,
            regenerated: 1
        )
        return await metrics.summary()
    }

    private static func memoryLimitPressure(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let payloadSize = 2 * 1024 * 1024
        let memoryLimit = YCache.Configuration.defaultMemoryMaximumCost
        let storageLimit = YCache.Configuration.defaultStorageMaximumByteCount
        let retainedMemoryCapacity = memoryLimit / payloadSize
        let writeCount = retainedMemoryCapacity + 12
        let cache = YCache(storageDirectory: context.rootDirectory)

        try require(cache.configuration.memoryMaximumCost == memoryLimit, "Default memory limit was not configured.")
        try require(cache.configuration.memoryMaximumEntryCount == nil, "Default memory entry count should be unbounded.")
        try require(cache.configuration.storageMaximumByteCount == storageLimit, "Default storage limit was not configured.")

        for index in 0..<writeCount {
            let key = memoryPressureKey(index)
            let expected = DeterministicPayload.data(
                seed: context.seed,
                index: index,
                byteCount: payloadSize
            )
            let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                expected
            }
            try require(resolved.source == .generated, "Memory pressure write was not generated.")
            try require(resolved.value == expected, "Memory pressure write returned changed data.")
        }

        let newestIndex = writeCount - 1
        let newest = try await cache.resolve(for: memoryPressureKey(newestIndex), codec: DataCodec()) {
            throw StressFailure("Newest memory pressure entry should be cached.")
        }
        let newestExpected = DeterministicPayload.data(
            seed: context.seed,
            index: newestIndex,
            byteCount: payloadSize
        )
        try require(newest.source == .memory, "Newest entry was not retained in memory under default limit.")
        try require(newest.value == newestExpected, "Newest memory pressure entry changed.")

        let oldest = try await cache.resolve(for: memoryPressureKey(0), codec: DataCodec()) {
            throw StressFailure("Oldest memory pressure entry should be persisted to storage.")
        }
        let oldestExpected = DeterministicPayload.data(
            seed: context.seed,
            index: 0,
            byteCount: payloadSize
        )
        try require(oldest.source == .storage, "Oldest entry was not evicted from memory to storage.")
        try require(oldest.value == oldestExpected, "Oldest memory pressure entry changed.")

        let sentinelKey = memoryPressureKey(writeCount)
        let sentinel = DeterministicPayload.data(
            seed: context.seed,
            index: writeCount,
            byteCount: payloadSize
        )
        let sentinelValue = try await cache.value(for: sentinelKey, codec: DataCodec()) {
            sentinel
        }
        try require(sentinelValue == sentinel, "Sentinel write after memory pressure changed data.")

        let usage = try await cache.storageUsage()
        try require(usage.maximumByteCount == storageLimit, "Default storage maximum was not reported.")
        try require(usage.byteCount <= storageLimit, "Default storage limit was exceeded during memory pressure.")
        try require(usage.entryCount > 0, "Memory pressure left no storage entries.")

        return StressScenarioSummary(
            operations: writeCount + 4,
            generatedCount: writeCount + 1,
            memoryHitCount: 1,
            storageHitCount: 1,
            removedCount: max(0, writeCount - retainedMemoryCapacity),
            message: "default memory limit \(memoryLimit) bytes, payload \(payloadSize) bytes"
        )
    }

    private static func oversizedEntryPressure(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let maximumByteCount = quotaPayloadSize(for: context.profile)
        let oversizedByteCount = maximumByteCount + max(1024, maximumByteCount / 2)
        let writeCount = min(context.profile.keyCount, max(context.profile.concurrency * 4, 64))
        let cache = YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        )
        let indexes = Array(0..<writeCount)

        try await runBounded(indexes, limit: context.profile.concurrency) { index in
            let key = quotaKey("oversized", index)
            let oversized = DeterministicPayload.data(
                seed: context.seed,
                index: index,
                byteCount: oversizedByteCount
            )
            let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
                oversized
            }
            try require(resolved.value == oversized, "Oversized write returned changed data.")
        }

        let usage = try await cache.storageUsage()
        try require(usage.byteCount == 0, "Oversized entries should not remain in storage.")
        try require(usage.entryCount == 0, "Oversized entries left metadata behind.")
        let temporaryFileCount = try managedFileCount(in: context.rootDirectory, suffix: ".tmp")
        try require(temporaryFileCount == 0, "Oversized writes left temporary files behind.")

        let sentinelKey = quotaKey("oversized-sentinel", 0)
        let sentinel = DeterministicPayload.data(
            seed: context.seed,
            index: writeCount + 10,
            byteCount: maximumByteCount
        )
        let stored = try await YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        ).resolve(for: sentinelKey, codec: DataCodec()) {
            sentinel
        }
        try require(stored.value == sentinel, "Sentinel write after oversized pressure changed data.")
        let persisted = try await YCache(
            storageDirectory: context.rootDirectory,
            storageMaximumByteCount: maximumByteCount
        ).resolve(for: sentinelKey, codec: DataCodec()) {
            throw StressFailure("Sentinel after oversized pressure was not persisted.")
        }
        try require(persisted.source == .storage, "Sentinel after oversized pressure was not read from storage.")
        try require(persisted.value == sentinel, "Sentinel after oversized pressure changed on disk.")

        return StressScenarioSummary(
            operations: writeCount + 4,
            generatedCount: writeCount + 1,
            storageHitCount: 1,
            removedCount: writeCount
        )
    }

    private static func corruptionRecovery(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        var summary = StressScenarioSummary()

        let dataMismatchRoot = context.rootDirectory.appendingPathComponent("data-mismatch", isDirectory: true)
        try FileManager.default.createDirectory(at: dataMismatchRoot, withIntermediateDirectories: true)
        let dataMismatchKey = CacheKey(namespace: "stress-corruption", identity: "data-mismatch")
        let original = DeterministicPayload.data(seed: context.seed, index: 1, byteCount: 4 * 1024)
        let regenerated = DeterministicPayload.data(seed: context.seed, index: 2, byteCount: 4 * 1024)
        try await YCache(storageDirectory: dataMismatchRoot).store(original, for: dataMismatchKey, codec: DataCodec())
        let dataURL = try firstManagedFile(in: dataMismatchRoot, suffix: ".data")
        try Data("corrupt-data".utf8).write(to: dataURL)

        let recovered = try await YCache(storageDirectory: dataMismatchRoot)
            .resolve(for: dataMismatchKey, codec: DataCodec()) {
                regenerated
            }
        try require(recovered.source == .generated, "Data corruption was not treated as a miss.")
        try require(recovered.value == regenerated, "Data corruption recovery returned the wrong value.")
        summary.operations += 2
        summary.generatedCount += 1
        summary.regeneratedCount += 1

        let strictRoot = context.rootDirectory.appendingPathComponent("strict-data-mismatch", isDirectory: true)
        try FileManager.default.createDirectory(at: strictRoot, withIntermediateDirectories: true)
        let strictKey = CacheKey(namespace: "stress-corruption", identity: "strict")
        try await YCache(storageDirectory: strictRoot).store(original, for: strictKey, codec: DataCodec())
        let strictDataURL = try firstManagedFile(in: strictRoot, suffix: ".data")
        try Data("strict-corrupt-data".utf8).write(to: strictDataURL)
        var strictErrorWasThrown = false
        do {
            let options = YCache.Options(readFailurePolicy: .throwError)
            _ = try await YCache(storageDirectory: strictRoot)
                .resolve(for: strictKey, codec: DataCodec(), options: options) {
                    regenerated
                }
        } catch {
            strictErrorWasThrown = true
        }
        try require(strictErrorWasThrown, "Strict read failure policy did not throw.")
        summary.operations += 1

        let metadataRoot = context.rootDirectory.appendingPathComponent("metadata-mismatch", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
        let metadataKey = CacheKey(namespace: "stress-corruption", identity: "metadata")
        try await YCache(storageDirectory: metadataRoot).store(original, for: metadataKey, codec: DataCodec())
        let metadataURL = try firstManagedFile(in: metadataRoot, suffix: ".metadata.json")
        try Data("{ not-json".utf8).write(to: metadataURL)
        let metadataRecovered = try await YCache(storageDirectory: metadataRoot)
            .resolve(for: metadataKey, codec: DataCodec()) {
                regenerated
            }
        try require(metadataRecovered.source == .generated, "Metadata corruption was not treated as a miss.")
        try require(metadataRecovered.value == regenerated, "Metadata corruption recovery returned the wrong value.")
        summary.operations += 2
        summary.generatedCount += 1
        summary.regeneratedCount += 1

        return summary
    }

    private static func cancellationChurn(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let cache = YCache(storageDirectory: context.rootDirectory)
        let key = CacheKey(namespace: "stress-cancellation", identity: "shared")
        let payload = DeterministicPayload.data(seed: context.seed, index: 99, byteCount: 8 * 1024)
        let taskCount = max(32, min(context.profile.singleFlightFanout, context.profile.concurrency * 4))
        let counter = StressCounter()

        let tasks = (0..<taskCount).map { _ in
            Task { () -> Result<Data, any Error> in
                do {
                    let value = try await cache.value(for: key, codec: DataCodec()) {
                        _ = await counter.increment()
                        try await Task.sleep(nanoseconds: 50_000_000)
                        return payload
                    }
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        for (index, task) in tasks.enumerated() where index.isMultiple(of: 3) {
            task.cancel()
        }

        var successCount = 0
        var cancelledCount = 0
        for task in tasks {
            switch await task.value {
            case .success(let value):
                try require(value == payload, "Cancellation churn returned a changed payload.")
                successCount += 1
            case .failure(let error):
                if error is CancellationError {
                    cancelledCount += 1
                } else {
                    throw error
                }
            }
        }

        try require(successCount > 0, "Cancellation churn produced no successful readers.")
        let generatorCount = await counter.value
        try require(generatorCount == 1, "Cancellation churn ran the shared generator more than once.")

        let afterCancellation = try await cache.resolve(for: key, codec: DataCodec()) {
            throw StressFailure("Post-cancellation read should hit the cache.")
        }
        try require(afterCancellation.value == payload, "Post-cancellation read returned a changed payload.")
        try require(afterCancellation.source == .memory || afterCancellation.source == .storage, "Post-cancellation read did not hit cache.")

        return StressScenarioSummary(
            operations: taskCount + 1,
            generatedCount: successCount,
            memoryHitCount: afterCancellation.source == .memory ? 1 : 0,
            storageHitCount: afterCancellation.source == .storage ? 1 : 0,
            cancelledCount: cancelledCount
        )
    }

    private static func cancellationAwareSingleFlight(
        context: StressScenarioContext
    ) async throws -> StressScenarioSummary {
        let cache = YCache(storageDirectory: context.rootDirectory)
        let options = YCache.Options(singleFlightPolicy: .cancelWhenNoWaiters)
        let metrics = StressMetrics()

        let partialKey = CacheKey(namespace: "stress-cancellation-aware", identity: "partial")
        let partialPayload = DeterministicPayload.data(seed: context.seed, index: 201, byteCount: 8 * 1024)
        let partialCounter = StressCounter()
        let partialGate = StressGate()

        let cancelledWaiter = Task {
            try await cache.resolve(for: partialKey, codec: DataCodec(), options: options) {
                _ = await partialCounter.increment()
                await partialGate.wait()
                return partialPayload
            }
        }
        await partialCounter.waitUntil(1)

        let survivingWaiter = Task {
            try await cache.resolve(for: partialKey, codec: DataCodec(), options: options) {
                _ = await partialCounter.increment()
                await partialGate.wait()
                return partialPayload
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        cancelledWaiter.cancel()
        try await requireCancellation(cancelledWaiter)
        await partialGate.open()

        let survived = try await survivingWaiter.value
        let partialGeneratorCount = await partialCounter.value
        try require(survived.value == partialPayload, "Surviving waiter received the wrong payload.")
        try require(survived.wasSharedGeneration, "Surviving waiter did not join the shared generation.")
        try require(partialGeneratorCount == 1, "Partial cancellation restarted the producer unexpectedly.")
        await metrics.recordOperation(operations: 2, generated: 1, cancelled: 1)

        let allCancelKey = CacheKey(namespace: "stress-cancellation-aware", identity: "all-cancel")
        let allCancelPayload = DeterministicPayload.data(seed: context.seed, index: 202, byteCount: 8 * 1024)
        let allCancelCounter = StressCounter()
        let cancellationProbe = StressCancellationProbe()

        let firstCancelled = Task {
            try await cache.resolve(for: allCancelKey, codec: DataCodec(), options: options) {
                _ = await allCancelCounter.increment()
                do {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                } catch is CancellationError {
                    await cancellationProbe.markObserved()
                    throw CancellationError()
                }
            }
        }
        await allCancelCounter.waitUntil(1)

        let secondCancelled = Task {
            try await cache.resolve(for: allCancelKey, codec: DataCodec(), options: options) {
                _ = await allCancelCounter.increment()
                do {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                } catch is CancellationError {
                    await cancellationProbe.markObserved()
                    throw CancellationError()
                }
            }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        firstCancelled.cancel()
        secondCancelled.cancel()
        try await requireCancellation(firstCancelled)
        try await requireCancellation(secondCancelled)
        await cancellationProbe.waitUntilObserved()

        let regenerated = try await cache.resolve(for: allCancelKey, codec: DataCodec(), options: options) {
            _ = await allCancelCounter.increment()
            return allCancelPayload
        }
        let allCancelGeneratorCount = await allCancelCounter.value
        try require(regenerated.source == .generated, "Re-request after full cancellation did not regenerate.")
        try require(regenerated.value == allCancelPayload, "Regenerated payload changed after full cancellation.")
        try require(allCancelGeneratorCount == 2, "Full cancellation left stale in-flight state.")
        await metrics.recordOperation(operations: 3, generated: 1, regenerated: 1, cancelled: 2)

        let nonCooperativeKey = CacheKey(namespace: "stress-cancellation-aware", identity: "non-cooperative")
        let nonCooperativePayload = DeterministicPayload.data(seed: context.seed, index: 203, byteCount: 8 * 1024)
        let nonCooperativeCounter = StressCounter()
        let nonCooperativeReturned = StressGate()

        let nonCooperative = Task {
            try await cache.resolve(for: nonCooperativeKey, codec: DataCodec(), options: options) {
                _ = await nonCooperativeCounter.increment()
                try? await Task.sleep(nanoseconds: 25_000_000)
                await nonCooperativeReturned.open()
                return nonCooperativePayload
            }
        }
        await nonCooperativeCounter.waitUntil(1)
        nonCooperative.cancel()
        try await requireCancellation(nonCooperative)
        await nonCooperativeReturned.wait()

        do {
            _ = try await cache.resolve(
                for: nonCooperativeKey,
                codec: DataCodec(),
                options: YCache.Options(
                    lookupPolicy: .cacheOnly,
                    singleFlightPolicy: .cancelWhenNoWaiters
                )
            ) {
                nonCooperativePayload
            }
            throw StressFailure("Non-cooperative cancelled result was cached.")
        } catch YCache.Error.cacheMiss {
        }
        await metrics.recordOperation(operations: 2, cancelled: 1)

        let randomCount = max(16, min(context.profile.concurrency * 2, context.profile.keyCount))
        let randomTasks = (0..<randomCount).map { index in
            Task { () -> Result<Data, any Error> in
                let key = CacheKey(namespace: "stress-cancellation-aware-random", identity: "\(index)")
                let payload = DeterministicPayload.data(seed: context.seed, index: 300 + index, byteCount: 4 * 1024)
                do {
                    let value = try await cache.value(for: key, codec: DataCodec(), options: options) {
                        try await Task.sleep(nanoseconds: UInt64((index % 5) + 1) * 2_000_000)
                        try Task.checkCancellation()
                        return payload
                    }
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            }
        }

        try await Task.sleep(nanoseconds: 2_000_000)
        for (index, task) in randomTasks.enumerated() where index.isMultiple(of: 4) {
            task.cancel()
        }

        var randomCancelled = 0
        var randomSucceeded = 0
        for task in randomTasks {
            switch await task.value {
            case .success:
                randomSucceeded += 1
            case .failure(let error):
                if error is CancellationError {
                    randomCancelled += 1
                } else {
                    throw error
                }
            }
        }

        for index in 0..<randomCount {
            let key = CacheKey(namespace: "stress-cancellation-aware-random", identity: "\(index)")
            let payload = DeterministicPayload.data(seed: context.seed, index: 300 + index, byteCount: 4 * 1024)
            let value = try await cache.value(for: key, codec: DataCodec(), options: options) {
                payload
            }
            try require(value == payload, "Random cancellation re-request returned a changed payload.")
        }

        await metrics.recordOperation(
            operations: randomCount * 2,
            generated: randomSucceeded,
            regenerated: randomCancelled,
            cancelled: randomCancelled
        )

        return await metrics.summary()
    }
}

private enum ArtifactKind: Sendable {
    case data
    case codableJSON
    case codablePropertyList
    case jpeg
    case png
}

private func artifactKind(for index: Int) -> ArtifactKind {
    #if canImport(UIKit) || canImport(AppKit)
    switch index % 5 {
    case 0: .data
    case 1: .codableJSON
    case 2: .codablePropertyList
    case 3: .jpeg
    default: .png
    }
    #else
    switch index % 3 {
    case 0: .data
    case 1: .codableJSON
    default: .codablePropertyList
    }
    #endif
}

private func artifactKey(_ index: Int) -> CacheKey {
    CacheKey(namespace: "stress-artifacts", identity: "artifact")
        .variant("index", index)
        .version("schema", 1)
}

private func trimKey(_ index: Int) -> CacheKey {
    CacheKey(namespace: "stress-trim", identity: "entry")
        .variant("index", index)
        .version("schema", 1)
}

private func quotaKey(_ prefix: String, _ index: Int) -> CacheKey {
    CacheKey(namespace: "stress-quota", identity: prefix)
        .variant("index", index)
        .version("schema", 1)
}

private func memoryPressureKey(_ index: Int) -> CacheKey {
    CacheKey(namespace: "stress-memory-pressure", identity: "entry")
        .variant("index", index)
        .version("schema", 1)
}

private func quotaPayloadSize(for profile: StressProfile) -> Int {
    min(max(profile.minimumPayloadByteCount * 8, 8 * 1024), 32 * 1024)
}

#if canImport(UIKit) || canImport(AppKit)
private func imageSize(for index: Int) -> StressImageSize {
    StressImageSize(width: 8 + (index % 9), height: 8 + (index % 7))
}
#endif

private func runBounded<Element: Sendable>(
    _ elements: [Element],
    limit: Int,
    operation: @escaping @Sendable (Element) async throws -> Void
) async throws {
    var iterator = elements.makeIterator()
    let limit = max(1, limit)

    try await withThrowingTaskGroup(of: Void.self) { group in
        var activeCount = 0

        while activeCount < limit, let element = iterator.next() {
            activeCount += 1
            group.addTask {
                try await operation(element)
            }
        }

        while activeCount > 0 {
            try await group.next()
            activeCount -= 1

            if let element = iterator.next() {
                activeCount += 1
                group.addTask {
                    try await operation(element)
                }
            }
        }
    }
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw StressFailure(message)
    }
}

private func requireCancellation<T>(
    _ task: Task<T, any Error>
) async throws {
    do {
        _ = try await task.value
        throw StressFailure("Expected CancellationError.")
    } catch is CancellationError {
    }
}

private func firstManagedFile(in rootDirectory: URL, suffix: String) throws -> URL {
    guard let enumerator = FileManager.default.enumerator(
        at: rootDirectory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        throw StressFailure("Unable to enumerate generated cache files.")
    }

    var matches: [URL] = []
    for case let url as URL in enumerator {
        guard url.lastPathComponent.hasSuffix(suffix),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else {
            continue
        }
        matches.append(url)
    }

    guard let first = matches.sorted(by: { $0.path < $1.path }).first else {
        throw StressFailure("Expected generated cache file was missing.")
    }
    return first
}

private func managedFileCount(in rootDirectory: URL, suffix: String) throws -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: rootDirectory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return 0
    }

    var count = 0
    for case let url as URL in enumerator {
        guard url.lastPathComponent.hasSuffix(suffix),
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else {
            continue
        }
        count += 1
    }
    return count
}

private actor StressCounter {
    private var count = 0
    private var waiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var value: Int {
        count
    }

    @discardableResult
    func increment() -> Int {
        count += 1
        resumeSatisfiedWaiters()
        return count
    }

    func waitUntil(_ target: Int) async {
        guard count < target else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append((target: target, continuation: continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in waiters {
            if count >= waiter.target {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}

private actor StressGate {
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

private actor StressCancellationProbe {
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

    func waitUntilObserved() async {
        guard !observed else {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private actor StressMetrics {
    private var operations = 0
    private var generatedCount = 0
    private var memoryHitCount = 0
    private var storageHitCount = 0
    private var regeneratedCount = 0
    private var removedCount = 0
    private var cancelledCount = 0

    func record(
        _ source: YCache.Source,
        operations: Int = 1,
        removed: Int = 0,
        regenerated: Int = 0,
        cancelled: Int = 0
    ) {
        recordOperation(
            operations: operations,
            generated: source == .generated ? 1 : 0,
            memory: source == .memory ? 1 : 0,
            storage: source == .storage ? 1 : 0,
            removed: removed,
            regenerated: regenerated,
            cancelled: cancelled
        )
    }

    func recordOperation(
        operations: Int = 1,
        generated: Int = 0,
        memory: Int = 0,
        storage: Int = 0,
        removed: Int = 0,
        regenerated: Int = 0,
        cancelled: Int = 0
    ) {
        self.operations += operations
        self.generatedCount += generated
        self.memoryHitCount += memory
        self.storageHitCount += storage
        self.removedCount += removed
        self.regeneratedCount += regenerated
        self.cancelledCount += cancelled
    }

    func summary(
        operations: Int? = nil,
        additionalOperations: Int = 0
    ) -> StressScenarioSummary {
        StressScenarioSummary(
            operations: (operations ?? self.operations) + additionalOperations,
            generatedCount: generatedCount,
            memoryHitCount: memoryHitCount,
            storageHitCount: storageHitCount,
            regeneratedCount: regeneratedCount,
            removedCount: removedCount,
            cancelledCount: cancelledCount
        )
    }
}
