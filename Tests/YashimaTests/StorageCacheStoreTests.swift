import Foundation
import Testing
@testable import Yashima

@Test func storageStorePersistsDataAndMetadata() async throws {
    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    try await withStorageStore(now: fixedDate) { store, _ in
        let identity = storageIdentity("persist")
        let data = Data("cached-data".utf8)

        let metadata = try await store.store(data, for: identity, cost: 11)
        let loaded = try await store.loadData(for: identity)
        let location = await store.location(for: identity)

        #expect(loaded?.data == data)
        #expect(loaded?.metadata == metadata)
        #expect(metadata.schemaVersion == StoredCacheEntryMetadata.currentSchemaVersion)
        #expect(metadata.entryHash == identity.entryHash)
        #expect(metadata.keyHash == identity.keyHash.rawValue)
        #expect(metadata.namespace == identity.namespace)
        #expect(metadata.byteCount == data.count)
        #expect(metadata.cost == 11)
        #expect(metadata.createdAt == fixedDate)
        #expect(metadata.lastAccessedAt == fixedDate)
        #expect(metadata.codecIdentifier == identity.codecIdentifier)
        #expect(metadata.contentDigest == StableDigest.sha256Hex(data))
        #expect(fileExists(at: location.dataURL))
        #expect(fileExists(at: location.metadataURL))
        #expect(location.dataURL.lastPathComponent == identity.dataFileName)
        #expect(location.metadataURL.lastPathComponent == identity.metadataFileName)
    }
}

@Test func storageStoreUpdatesLastAccessedAtOnLoad() async throws {
    let clock = StorageTestClock(Date(timeIntervalSince1970: 1_800_000_000))

    try await withStorageStore(nowProvider: { clock.date }) { store, _ in
        let identity = storageIdentity("last-accessed")

        let storedMetadata = try await store.store(Data("value".utf8), for: identity)
        clock.date = Date(timeIntervalSince1970: 1_800_000_100)

        let loaded = try await store.loadData(for: identity)
        let metadata = try await store.metadata(for: identity)

        #expect(storedMetadata.lastAccessedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(loaded?.metadata.lastAccessedAt == Date(timeIntervalSince1970: 1_800_000_100))
        #expect(metadata?.lastAccessedAt == Date(timeIntervalSince1970: 1_800_000_100))
    }
}

@Test func storageStoreReturnsNilForMissingEntry() async throws {
    try await withStorageStore { store, _ in
        let loaded = try await store.loadData(for: storageIdentity("missing"))

        #expect(loaded == nil)
    }
}

@Test func storageStoreOverwritesExistingEntry() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("overwrite")
        let first = Data("first".utf8)
        let second = Data("second-value".utf8)

        try await store.store(first, for: identity, cost: 5)
        let metadata = try await store.store(second, for: identity, cost: 12)
        let loaded = try await store.loadData(for: identity)

        #expect(loaded?.data == second)
        #expect(loaded?.metadata == metadata)
        #expect(loaded?.metadata.byteCount == second.count)
        #expect(loaded?.metadata.cost == 12)
        #expect(loaded?.metadata.contentDigest == StableDigest.sha256Hex(second))
    }
}

@Test func storageStoreThrowsForCodecMetadataMismatchAndRemovesEntry() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("codec-mismatch")
        let data = Data("value".utf8)

        var metadata = try await store.store(data, for: identity)
        let location = await store.location(for: identity)
        metadata.codecIdentifier = "different-codec-v1"
        try writeMetadata(metadata, to: location.metadataURL)

        do {
            _ = try await store.loadData(for: identity)
            Issue.record("Expected metadata mismatch to throw.")
        } catch StorageCacheStoreError.metadataMismatch {
        }

        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreThrowsForCorruptedDataAndRemovesEntry() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("corrupted-data")
        let location = await store.location(for: identity)

        try await store.store(Data("original".utf8), for: identity)
        try Data("tampered".utf8).write(to: location.dataURL)

        do {
            _ = try await store.loadData(for: identity)
            Issue.record("Expected corrupted data to throw.")
        } catch StorageCacheStoreError.dataMismatch {
        }

        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreThrowsForCorruptedMetadataAndRemovesEntry() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("corrupted-metadata")
        let location = await store.location(for: identity)

        try await store.store(Data("original".utf8), for: identity)
        try Data("{not-json".utf8).write(to: location.metadataURL)

        do {
            _ = try await store.loadData(for: identity)
            Issue.record("Expected corrupted metadata to throw.")
        } catch {
        }

        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreThrowsForOrphanedDataAndRemovesIt() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("missing-metadata")
        let location = await store.location(for: identity)

        try await store.store(Data("orphan".utf8), for: identity)
        try FileManager.default.removeItem(at: location.metadataURL)

        do {
            _ = try await store.loadData(for: identity)
            Issue.record("Expected missing metadata to throw.")
        } catch StorageCacheStoreError.missingMetadata {
        }

        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreThrowsForMissingDataAndRemovesMetadata() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("missing-data")
        let location = await store.location(for: identity)

        try await store.store(Data("metadata-only".utf8), for: identity)
        try FileManager.default.removeItem(at: location.dataURL)

        do {
            _ = try await store.loadData(for: identity)
            Issue.record("Expected missing data to throw.")
        } catch StorageCacheStoreError.missingData {
        }

        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreUsageReportsValidEntryCountBytesAndMaximum() async throws {
    try await withStorageStore(maximumByteCount: 20) { store, _ in
        try await store.store(Data("first".utf8), for: storageIdentity("usage-first"))
        try await store.store(Data("second".utf8), for: storageIdentity("usage-second"))

        let usage = try await store.usage()

        #expect(usage.byteCount == 11)
        #expect(usage.entryCount == 2)
        #expect(usage.maximumByteCount == 20)
    }
}

@Test func storageStoreTrimsLeastRecentlyUsedEntriesWhenOverByteLimit() async throws {
    let clock = StorageTestClock(Date(timeIntervalSince1970: 1_800_000_000))

    try await withStorageStore(nowProvider: { clock.date }, maximumByteCount: 8) { store, _ in
        let first = storageIdentity("lru-first")
        let second = storageIdentity("lru-second")
        let third = storageIdentity("lru-third")

        try await store.store(Data("1111".utf8), for: first)
        clock.date = Date(timeIntervalSince1970: 1_800_000_010)
        try await store.store(Data("2222".utf8), for: second)
        clock.date = Date(timeIntervalSince1970: 1_800_000_020)
        _ = try await store.loadData(for: first)
        clock.date = Date(timeIntervalSince1970: 1_800_000_030)
        try await store.store(Data("3333".utf8), for: third)

        let firstValue = try await store.loadData(for: first)?.data
        let secondValue = try await store.loadData(for: second)?.data
        let thirdValue = try await store.loadData(for: third)?.data
        let usage = try await store.usage()

        #expect(firstValue == Data("1111".utf8))
        #expect(secondValue == nil)
        #expect(thirdValue == Data("3333".utf8))
        #expect(usage.byteCount == 8)
        #expect(usage.entryCount == 2)
    }
}

@Test func storageStoreRemovesOversizedEntryWhenByteLimitCannotFitIt() async throws {
    try await withStorageStore(maximumByteCount: 3) { store, _ in
        let identity = storageIdentity("oversized")

        try await store.store(Data("1234".utf8), for: identity)

        let loaded = try await store.loadData(for: identity)
        let usage = try await store.usage()

        #expect(loaded == nil)
        #expect(usage.byteCount == 0)
        #expect(usage.entryCount == 0)
    }
}

@Test func storageStoreCleansInvalidMetadataEntriesDuringUsageScan() async throws {
    try await withStorageStore { store, _ in
        let missingMetadata = storageIdentity("scan-missing-metadata")
        let missingData = storageIdentity("scan-missing-data")
        let corruptedMetadata = storageIdentity("scan-corrupted-metadata")

        try await store.store(Data("orphan".utf8), for: missingMetadata)
        try await store.store(Data("metadata-only".utf8), for: missingData)
        try await store.store(Data("metadata".utf8), for: corruptedMetadata)

        let missingMetadataLocation = await store.location(for: missingMetadata)
        let missingDataLocation = await store.location(for: missingData)
        let corruptedMetadataLocation = await store.location(for: corruptedMetadata)

        try FileManager.default.removeItem(at: missingMetadataLocation.metadataURL)
        try FileManager.default.removeItem(at: missingDataLocation.dataURL)
        try Data("{not-json".utf8).write(to: corruptedMetadataLocation.metadataURL)

        let usage = try await store.usage()

        #expect(usage.byteCount == 0)
        #expect(usage.entryCount == 0)
        #expect(!fileExists(at: missingMetadataLocation.dataURL))
        #expect(!fileExists(at: missingDataLocation.metadataURL))
        #expect(!fileExists(at: corruptedMetadataLocation.metadataURL))
    }
}

@Test func storageStoreUsageDoesNotValidateStoredDataDigest() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("usage-digest-mismatch")
        let location = await store.location(for: identity)

        try await store.store(Data("original".utf8), for: identity)
        try Data("tampered".utf8).write(to: location.dataURL)

        let usage = try await store.usage()

        #expect(usage.byteCount == Data("original".utf8).count)
        #expect(usage.entryCount == 1)
        #expect(fileExists(at: location.dataURL))
        #expect(fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreTrimTieBreaksByEntryHashWhenAccessDatesMatch() async throws {
    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    try await withStorageStore(now: fixedDate, maximumByteCount: 4) { store, _ in
        let first = storageIdentity("tie-first")
        let second = storageIdentity("tie-second")
        let expectedRemoved = [first, second].min { $0.entryHash < $1.entryHash }
        let expectedKept = expectedRemoved == first ? second : first

        try await store.store(Data("1111".utf8), for: first)
        try await store.store(Data("2222".utf8), for: second)

        let removedValue = try await store.loadData(for: expectedRemoved!)?.data
        let keptValue = try await store.loadData(for: expectedKept)?.data
        let usage = try await store.usage()

        #expect(removedValue == nil)
        #expect(keptValue != nil)
        #expect(usage.byteCount == 4)
        #expect(usage.entryCount == 1)
    }
}

@Test func storageStoreRemoveValueDeletesDataAndMetadata() async throws {
    try await withStorageStore { store, _ in
        let identity = storageIdentity("remove")
        let location = await store.location(for: identity)

        try await store.store(Data("value".utf8), for: identity)

        let firstRemoval = try await store.removeValue(for: identity)
        let secondRemoval = try await store.removeValue(for: identity)
        let loaded = try await store.loadData(for: identity)

        #expect(firstRemoval)
        #expect(!secondRemoval)
        #expect(loaded == nil)
        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
    }
}

@Test func storageStoreRemoveAllDeletesManagedDirectoriesOnly() async throws {
    try await withStorageStore { store, rootDirectory in
        let identity = storageIdentity("remove-all")
        let unmanagedFile = rootDirectory.appendingPathComponent("unmanaged.txt")

        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: unmanagedFile)
        try await store.store(Data("value".utf8), for: identity)
        let location = await store.location(for: identity)

        try await store.removeAll()

        #expect(fileExists(at: rootDirectory))
        #expect(fileExists(at: unmanagedFile))
        #expect(!fileExists(at: location.dataURL))
        #expect(!fileExists(at: location.metadataURL))
        #expect(try await store.loadData(for: identity) == nil)
    }
}

private func withStorageStore<T>(
    now: Date = Date(timeIntervalSince1970: 1_800_000_100),
    maximumByteCount: Int? = nil,
    _ operation: (StorageCacheStore, URL) async throws -> T
) async throws -> T {
    let clock = StorageTestClock(now)
    return try await withStorageStore(
        nowProvider: { clock.date },
        maximumByteCount: maximumByteCount,
        operation
    )
}

private func withStorageStore<T>(
    nowProvider: @escaping @Sendable () -> Date,
    maximumByteCount: Int? = nil,
    _ operation: (StorageCacheStore, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaStorageTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let store = StorageCacheStore(
        rootDirectory: rootDirectory,
        maximumByteCount: maximumByteCount,
        now: nowProvider
    )

    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    return try await operation(store, rootDirectory)
}

private func storageIdentity(_ name: String) -> CacheEntryIdentity {
    CacheEntryIdentity(
        key: CacheKey(namespace: "storage-tests", identity: name),
        codecIdentifier: "test-codec-v1"
    )
}

private final class StorageTestClock: @unchecked Sendable {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

private func writeMetadata(_ metadata: StoredCacheEntryMetadata, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(metadata)
    try data.write(to: url)
}

private func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
