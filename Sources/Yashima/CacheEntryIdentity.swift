import Foundation

struct CacheEntryIdentity: Sendable, Hashable, Codable {
    var entryHash: String
    var keyHash: CacheKeyHash
    var codecIdentifier: String

    init<C: CacheCodec>(key: CacheKey, codec: C) {
        self.init(key: key, codecIdentifier: codec.identifier)
    }

    init(key: CacheKey, codecIdentifier: String) {
        self.keyHash = key.stableHash
        self.codecIdentifier = codecIdentifier

        var writer = CacheCanonicalWriter()
        writer.appendString("yashima.cache-entry-identity.v1")
        writer.appendString("key")
        writer.appendData(key.canonicalRepresentation)
        writer.appendString("codec")
        writer.appendString(codecIdentifier)
        self.entryHash = StableDigest.sha256Hex(writer.data)
    }

    var dataFileName: String {
        "\(entryHash).data"
    }

    var metadataFileName: String {
        "\(entryHash).metadata.json"
    }
}

struct CacheKeyHash: Sendable, Hashable, Codable, RawRepresentable, CustomStringConvertible {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String {
        rawValue
    }
}
