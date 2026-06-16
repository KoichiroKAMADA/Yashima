import Foundation

actor StorageCacheStore {
    private let rootDirectory: URL
    private let maximumByteCount: Int?
    private let now: @Sendable () -> Date

    init(
        rootDirectory: URL,
        maximumByteCount: Int? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.rootDirectory = rootDirectory
        self.maximumByteCount = maximumByteCount.map { max(0, $0) }
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
        do {
            try writeAtomically(data, to: location.dataURL)
            try writeMetadata(metadata, to: location.metadataURL)
            if maximumByteCount != nil {
                try trimIfNeeded()
            }
        } catch {
            try? removeEntryFiles(at: location)
            throw error
        }

        return metadata
    }

    func loadData(for identity: CacheEntryIdentity) throws -> StoredCacheEntry? {
        let location = location(for: identity)

        guard var metadata = try metadata(for: identity) else {
            return nil
        }

        let data = try Data(contentsOf: location.dataURL)
        guard metadata.matches(data: data) else {
            try removeEntryFiles(at: location)
            throw StorageCacheStoreError.dataMismatch(entryHash: identity.entryHash)
        }

        let accessDate = now()
        if metadata.lastAccessedAt != accessDate {
            metadata.lastAccessedAt = accessDate
            try writeMetadata(metadata, to: location.metadataURL)
        }

        return StoredCacheEntry(data: data, metadata: metadata)
    }

    func metadata(for identity: CacheEntryIdentity) throws -> StoredCacheEntryMetadata? {
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

        return metadata
    }

    @discardableResult
    func removeValue(for identity: CacheEntryIdentity) throws -> Bool {
        let location = location(for: identity)
        let existed = fileExists(at: location.dataURL) || fileExists(at: location.metadataURL)
        try removeEntryFiles(at: location)
        return existed
    }

    func removeAll() throws {
        try removeManagedDirectories()
    }

    func removeAll(in namespace: String) throws {
        let entries = try validMetadataEntries()
        for metadata in entries where metadata.namespace == namespace {
            try removeEntryFiles(at: location(forEntryHash: metadata.entryHash))
        }
    }

    func usage() throws -> StorageCacheUsage {
        let entries = try validMetadataEntries()
        return usage(for: entries)
    }

    @discardableResult
    func trimIfNeeded() throws -> StorageCacheUsage {
        var entries = try validMetadataEntries()
        var currentUsage = usage(for: entries)

        guard let maximumByteCount else {
            return currentUsage
        }

        if currentUsage.byteCount <= maximumByteCount {
            return currentUsage
        }

        for metadata in entries.sortedForRemoval() {
            guard currentUsage.byteCount > maximumByteCount else {
                break
            }

            try removeEntryFiles(at: location(forEntryHash: metadata.entryHash))
            currentUsage.byteCount -= metadata.byteCount
            currentUsage.entryCount -= 1
        }

        entries = try validMetadataEntries()
        return usage(for: entries)
    }

    func location(for identity: CacheEntryIdentity) -> EntryLocation {
        location(forEntryHash: identity.entryHash)
    }
}

extension StorageCacheStore {
    struct EntryLocation: Sendable, Equatable {
        var dataURL: URL
        var metadataURL: URL
    }
}

struct StorageCacheUsage: Sendable, Equatable {
    var byteCount: Int
    var entryCount: Int
    var maximumByteCount: Int?
}

struct StoredCacheEntry: Sendable, Equatable {
    var data: Data
    var metadata: StoredCacheEntryMetadata
}

struct StoredCacheEntryMetadata: Sendable, Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var entryHash: String
    var keyHash: String
    var namespace: String
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
        self.namespace = identity.namespace
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
            && namespace == identity.namespace
            && codecIdentifier == identity.codecIdentifier
    }

    func matchesStoredLocation(entryHash expectedEntryHash: String) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && entryHash == expectedEntryHash
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
    var objectsDirectory: URL {
        rootDirectory.appendingPathComponent("objects", isDirectory: true)
    }

    var metadataDirectory: URL {
        rootDirectory.appendingPathComponent("metadata", isDirectory: true)
    }

    var tmpDirectory: URL {
        rootDirectory.appendingPathComponent("tmp", isDirectory: true)
    }

    func location(forEntryHash entryHash: String) -> EntryLocation {
        let first = String(entryHash.prefix(2))
        let second = String(entryHash.dropFirst(2).prefix(2))
        let objectDirectory = objectsDirectory
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)
        let metadataParentDirectory = metadataDirectory
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)

        return EntryLocation(
            dataURL: objectDirectory.appendingPathComponent("\(entryHash).data", isDirectory: false),
            metadataURL: metadataParentDirectory.appendingPathComponent("\(entryHash).metadata.json", isDirectory: false)
        )
    }

    func usage(for entries: [StoredCacheEntryMetadata]) -> StorageCacheUsage {
        StorageCacheUsage(
            byteCount: entries.reduce(0) { $0 + $1.byteCount },
            entryCount: entries.count,
            maximumByteCount: maximumByteCount
        )
    }

    func validMetadataEntries() throws -> [StoredCacheEntryMetadata] {
        try removeOrphanedDataFiles()

        guard fileExists(at: metadataDirectory) else {
            return []
        }

        var entries: [StoredCacheEntryMetadata] = []
        for metadataURL in try metadataFileURLs() {
            guard let entryHash = entryHash(fromMetadataURL: metadataURL) else {
                continue
            }

            let location = location(forEntryHash: entryHash)
            let metadata: StoredCacheEntryMetadata
            do {
                metadata = try readMetadata(from: metadataURL)
            } catch is DecodingError {
                try removeEntryFiles(at: location)
                continue
            }

            guard metadata.matchesStoredLocation(entryHash: entryHash),
                  fileExists(at: location.dataURL)
            else {
                try removeEntryFiles(at: location)
                continue
            }

            entries.append(metadata)
        }

        return entries
    }

    func removeManagedDirectories() throws {
        try removeFileIfPresent(at: objectsDirectory)
        try removeFileIfPresent(at: metadataDirectory)
        try removeFileIfPresent(at: tmpDirectory)
    }

    func metadataFileURLs() throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: metadataDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".metadata.json"),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else {
                continue
            }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    func removeOrphanedDataFiles() throws {
        guard fileExists(at: objectsDirectory),
              let enumerator = FileManager.default.enumerator(
                at: objectsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
              )
        else {
            return
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasSuffix(".data"),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  let entryHash = entryHash(fromDataURL: url)
            else {
                continue
            }

            let metadataURL = location(forEntryHash: entryHash).metadataURL
            if !fileExists(at: metadataURL) {
                try removeFileIfPresent(at: url)
            }
        }
    }

    func entryHash(fromMetadataURL url: URL) -> String? {
        let suffix = ".metadata.json"
        let fileName = url.lastPathComponent
        guard fileName.hasSuffix(suffix) else {
            return nil
        }
        return String(fileName.dropLast(suffix.count))
    }

    func entryHash(fromDataURL url: URL) -> String? {
        let suffix = ".data"
        let fileName = url.lastPathComponent
        guard fileName.hasSuffix(suffix) else {
            return nil
        }
        return String(fileName.dropLast(suffix.count))
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

private extension Array where Element == StoredCacheEntryMetadata {
    func sortedForRemoval() -> [StoredCacheEntryMetadata] {
        sorted { lhs, rhs in
            if lhs.lastAccessedAt != rhs.lastAccessedAt {
                return lhs.lastAccessedAt < rhs.lastAccessedAt
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.entryHash < rhs.entryHash
        }
    }
}
