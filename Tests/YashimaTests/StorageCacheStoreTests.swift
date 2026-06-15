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

@Test func storageStoreRemoveAllDeletesRootDirectory() async throws {
    try await withStorageStore { store, rootDirectory in
        try await store.store(Data("value".utf8), for: storageIdentity("remove-all"))

        #expect(fileExists(at: rootDirectory))

        try await store.removeAll()

        #expect(!fileExists(at: rootDirectory))
    }
}

private func withStorageStore<T>(
    now: Date = Date(timeIntervalSince1970: 1_800_000_100),
    _ operation: (StorageCacheStore, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaStorageTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let store = StorageCacheStore(rootDirectory: rootDirectory, now: { now })

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

private func writeMetadata(_ metadata: StoredCacheEntryMetadata, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(metadata)
    try data.write(to: url)
}

private func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
