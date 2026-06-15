import Foundation

actor StorageCacheStore {
    private let rootDirectory: URL
    private let now: @Sendable () -> Date

    init(rootDirectory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.rootDirectory = rootDirectory
        self.now = now
    }

    @discardableResult
    func store(
        _ data: Data,
        for identity: CacheEntryIdentity,
        cost: Int? = nil
    ) throws -> StoredCacheEntryMetadata {
        let metadata = StoredCacheEntryMetadata(
            identity: identity,
            byteCount: data.count,
            cost: cost,
            date: now(),
            contentDigest: StableDigest.sha256Hex(data)
        )
        let location = location(for: identity)

        try createParentDirectories(for: location)
        try writeAtomically(data, to: location.dataURL)
        try writeMetadata(metadata, to: location.metadataURL)

        return metadata
    }

    func loadData(for identity: CacheEntryIdentity) throws -> StoredCacheEntry? {
        let location = location(for: identity)

        guard fileExists(at: location.metadataURL) else {
            if fileExists(at: location.dataURL) {
                try removeFileIfPresent(at: location.dataURL)
                throw StorageCacheStoreError.missingMetadata(entryHash: identity.entryHash)
            }
            return nil
        }

        let metadata: StoredCacheEntryMetadata
        do {
            metadata = try readMetadata(from: location.metadataURL)
        } catch {
            try removeEntryFiles(at: location)
            throw error
        }

        guard metadata.matches(identity: identity) else {
            try removeEntryFiles(at: location)
            throw StorageCacheStoreError.metadataMismatch(
                expectedEntryHash: identity.entryHash,
                actualEntryHash: metadata.entryHash
            )
        }

        guard fileExists(at: location.dataURL) else {
            try removeEntryFiles(at: location)
            throw StorageCacheStoreError.missingData(entryHash: identity.entryHash)
        }

        let data = try Data(contentsOf: location.dataURL)
        guard metadata.matches(data: data) else {
            try removeEntryFiles(at: location)
            throw StorageCacheStoreError.dataMismatch(entryHash: identity.entryHash)
        }

        return StoredCacheEntry(data: data, metadata: metadata)
    }

    @discardableResult
    func removeValue(for identity: CacheEntryIdentity) throws -> Bool {
        let location = location(for: identity)
        let existed = fileExists(at: location.dataURL) || fileExists(at: location.metadataURL)
        try removeEntryFiles(at: location)
        return existed
    }

    func removeAll() throws {
        try removeFileIfPresent(at: rootDirectory)
    }

    func location(for identity: CacheEntryIdentity) -> EntryLocation {
        let first = String(identity.entryHash.prefix(2))
        let second = String(identity.entryHash.dropFirst(2).prefix(2))
        let objectDirectory = rootDirectory
            .appendingPathComponent("objects", isDirectory: true)
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)
        let metadataDirectory = rootDirectory
            .appendingPathComponent("metadata", isDirectory: true)
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)

        return EntryLocation(
            dataURL: objectDirectory.appendingPathComponent(identity.dataFileName, isDirectory: false),
            metadataURL: metadataDirectory.appendingPathComponent(identity.metadataFileName, isDirectory: false)
        )
    }
}

extension StorageCacheStore {
    struct EntryLocation: Sendable, Equatable {
        var dataURL: URL
        var metadataURL: URL
    }
}

struct StoredCacheEntry: Sendable, Equatable {
    var data: Data
    var metadata: StoredCacheEntryMetadata
}

struct StoredCacheEntryMetadata: Sendable, Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entryHash: String
    var keyHash: String
    var byteCount: Int
    var cost: Int?
    var createdAt: Date
    var lastAccessedAt: Date
    var codecIdentifier: String
    var contentDigest: String?

    init(
        identity: CacheEntryIdentity,
        byteCount: Int,
        cost: Int?,
        date: Date,
        contentDigest: String?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.entryHash = identity.entryHash
        self.keyHash = identity.keyHash.rawValue
        self.byteCount = byteCount
        self.cost = cost
        self.createdAt = date
        self.lastAccessedAt = date
        self.codecIdentifier = identity.codecIdentifier
        self.contentDigest = contentDigest
    }

    func matches(identity: CacheEntryIdentity) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && entryHash == identity.entryHash
            && keyHash == identity.keyHash.rawValue
            && codecIdentifier == identity.codecIdentifier
    }

    func matches(data: Data) -> Bool {
        byteCount == data.count
            && contentDigest == StableDigest.sha256Hex(data)
    }
}

enum StorageCacheStoreError: Error, Equatable {
    case missingMetadata(entryHash: String)
    case metadataMismatch(expectedEntryHash: String, actualEntryHash: String)
    case missingData(entryHash: String)
    case dataMismatch(entryHash: String)
}

private extension StorageCacheStore {
    var tmpDirectory: URL {
        rootDirectory.appendingPathComponent("tmp", isDirectory: true)
    }

    func createParentDirectories(for location: EntryLocation) throws {
        try createDirectory(at: location.dataURL.deletingLastPathComponent())
        try createDirectory(at: location.metadataURL.deletingLastPathComponent())
        try createDirectory(at: tmpDirectory)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    func writeMetadata(_ metadata: StoredCacheEntryMetadata, to destinationURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        try writeAtomically(data, to: destinationURL)
    }

    func readMetadata(from url: URL) throws -> StoredCacheEntryMetadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StoredCacheEntryMetadata.self, from: data)
    }

    func writeAtomically(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL = tmpDirectory.appendingPathComponent(
            "\(UUID().uuidString).tmp",
            isDirectory: false
        )
        try createDirectory(at: tmpDirectory)
        try data.write(to: temporaryURL)

        do {
            try replaceItem(at: destinationURL, withItemAt: temporaryURL)
        } catch {
            try? removeFileIfPresent(at: temporaryURL)
            throw error
        }
    }

    func replaceItem(at destinationURL: URL, withItemAt temporaryURL: URL) throws {
        if fileExists(at: destinationURL) {
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    func removeEntryFiles(at location: EntryLocation) throws {
        try removeFileIfPresent(at: location.dataURL)
        try removeFileIfPresent(at: location.metadataURL)
    }

    func removeFileIfPresent(at url: URL) throws {
        guard fileExists(at: url) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
