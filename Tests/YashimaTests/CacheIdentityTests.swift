import Foundation
import Testing
@testable import Yashima

private struct TestCodec: CacheCodec {
    var identifier: String

    func encode(_ value: Data) throws -> Data {
        value
    }

    func decode(_ data: Data) throws -> Data {
        data
    }
}

@Test func cacheKeyCanonicalizationIgnoresComponentOrder() {
    let first = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("size", "320x180")
        .variant("scale", 2)
        .version("renderer", 3)
        .version("palette", "standard")

    let reordered = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("scale", 2)
        .variant("size", "320x180")
        .version("palette", "standard")
        .version("renderer", 3)

    #expect(first.canonicalRepresentation == reordered.canonicalRepresentation)
    #expect(first.stableHash == reordered.stableHash)
    #expect(first == reordered)
    #expect(Set([first, reordered]).count == 1)
}

@Test func cacheKeyCanonicalizationKeepsVariantsAndVersionsDistinct() {
    let variant = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("renderer", 3)

    let version = CacheKey(namespace: "thumbnail", identity: "video-42")
        .version("renderer", 3)

    #expect(variant.canonicalRepresentation != version.canonicalRepresentation)
    #expect(variant.stableHash != version.stableHash)
}

@Test func cacheKeyCanonicalizationIsSafeForDelimiterLikeValues() {
    let first = CacheKey(namespace: "a|b", identity: "c")
        .variant("name", "x:y")
        .version("renderer", "1\n2")

    let second = CacheKey(namespace: "a", identity: "b|c")
        .variant("name:x", "y")
        .version("renderer", "1")
        .version("extra", "2")

    #expect(first.canonicalRepresentation != second.canonicalRepresentation)
    #expect(first.stableHash != second.stableHash)
}

@Test func cacheKeyStableHashUsesFixedDigestFormat() {
    let key = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("size", "320x180")
        .variant("scale", 2)
        .version("renderer", 3)

    #expect(key.stableHash.rawValue == "a02bbdf6fd55ad4512872772211b170d6693e8e80faefb18344ca7a3b0bd7791")
    #expect(key.stableIdentifier == key.stableHash.rawValue)
    #expect(key.stableHash.rawValue.count == 64)
    #expect(key.stableHash.rawValue.allSatisfy { $0.isHexDigit })
}

@Test func cacheKeyStableIdentifierUsesCanonicalKeyOnly() {
    let first = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("size", "320x180")
        .variant("scale", 2)
        .version("renderer", 3)
    let reordered = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("scale", 2)
        .variant("size", "320x180")
        .version("renderer", 3)
    let differentVersion = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("scale", 2)
        .variant("size", "320x180")
        .version("renderer", 4)

    #expect(first.stableIdentifier == reordered.stableIdentifier)
    #expect(first.stableIdentifier != differentVersion.stableIdentifier)
    #expect(first.stableIdentifier.count == 64)
    #expect(first.stableIdentifier.allSatisfy { $0.isHexDigit })
}

@Test func entryIdentityIncludesCodecIdentifier() {
    let key = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("size", "320x180")

    let jpeg = CacheEntryIdentity(key: key, codec: TestCodec(identifier: "image-jpeg-q85-v1"))
    let png = CacheEntryIdentity(key: key, codec: TestCodec(identifier: "image-png-v1"))

    #expect(jpeg.keyHash == png.keyHash)
    #expect(jpeg.keyHash.rawValue == key.stableIdentifier)
    #expect(jpeg.codecIdentifier == "image-jpeg-q85-v1")
    #expect(png.codecIdentifier == "image-png-v1")
    #expect(jpeg.entryHash != png.entryHash)
    #expect(jpeg.entryHash != key.stableIdentifier)
    #expect(png.entryHash != key.stableIdentifier)
}

@Test func sameKeyAndCodecProduceSameEntryIdentity() {
    let codec = TestCodec(identifier: "data-v1")
    let key = CacheKey(namespace: "analysis", identity: "summary-7")
        .variant("language", "ja")
        .version("algorithm", 4)

    let first = CacheEntryIdentity(key: key, codec: codec)
    let second = CacheEntryIdentity(key: key, codecIdentifier: codec.identifier)

    #expect(first == second)
    #expect(first.entryHash.count == 64)
    #expect(first.entryHash.allSatisfy { $0.isHexDigit })
}

@Test func entryIdentityStableHashUsesFixedDigestFormat() {
    let key = CacheKey(namespace: "thumbnail", identity: "video-42")
        .variant("size", "320x180")
        .variant("scale", 2)
        .version("renderer", 3)
    let identity = CacheEntryIdentity(key: key, codecIdentifier: "data-v1")

    #expect(identity.entryHash == "5f3a3ae57d96bbf2e16e62da269509d4f1638e6650f243676087636fb8a6a0a4")
    #expect(identity.keyHash.rawValue == key.stableHash.rawValue)
    #expect(identity.codecIdentifier == "data-v1")
}

@Test func entryIdentityFileNamesAreStableAndFileSystemSafe() {
    let key = CacheKey(namespace: "thumbnail", identity: "video/42")
        .variant("size", "320x180")
    let identity = CacheEntryIdentity(key: key, codecIdentifier: "image-jpeg-q85-v1")

    #expect(identity.dataFileName == "\(identity.entryHash).data")
    #expect(identity.metadataFileName == "\(identity.entryHash).metadata.json")
    #expect(identity.dataFileName.allSatisfy { character in
        character.isHexDigit || character == "." || character.isLetter
    })
    #expect(identity.metadataFileName.allSatisfy { character in
        character.isHexDigit || character == "." || character.isLetter
    })
}
