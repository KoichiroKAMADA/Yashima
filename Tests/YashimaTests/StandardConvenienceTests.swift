import Foundation
import Testing
import Yashima

#if canImport(UIKit)
import CoreGraphics
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreGraphics
#endif

@Test func dataConvenienceUsesDataCodecIdentityAndPersists() async throws {
    try await withStandardYCache { cache, rootDirectory in
        let key = standardKey("data")
        let generated = Data("hello-data".utf8)

        let value = try await cache.data(for: key) {
            generated
        }
        let resolved = try await cache.resolve(for: key, codec: DataCodec()) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted = try await newCache.data(for: key) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(value == generated)
        #expect(resolved.value == generated)
        #expect(resolved.source == .memory)
        #expect(resolved.metadata?.codecIdentifier == DataCodec().identifier)
        #expect(persisted == generated)
    }
}

@Test func compressedDataCodecRoundTripsAndPersistsLZFSEPayload() async throws {
    try await withStandardYCache { cache, rootDirectory in
        let key = standardKey("compressed-data")
        let codec = CompressedDataCodec()
        let generated = standardCompressibleHTMLData(repetitions: 160)

        let resolved = try await cache.resolve(for: key, codec: codec) {
            generated
        }
        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted = try await newCache.resolve(for: key, codec: codec) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }
        let storedData = try #require(try storedDataFiles(in: rootDirectory).first)

        #expect(resolved.value == generated)
        #expect(resolved.metadata?.codecIdentifier == codec.identifier)
        #expect(resolved.metadata?.cost == generated.count)
        #expect(persisted.value == generated)
        #expect(persisted.source == .storage)
        #expect(persisted.metadata?.cost == generated.count)
        #expect(storedData.count < generated.count)
    }
}

@Test func compressedDataCodecUsesDistinctIdentityFromDataCodec() async throws {
    try await withStandardYCache { cache, _ in
        let key = standardKey("compressed-data-distinct")
        let uncompressed = Data("plain-data".utf8)
        let compressed = standardCompressibleHTMLData(repetitions: 12)
        let compressedCodec = CompressedDataCodec()

        let dataValue = try await cache.data(for: key) {
            uncompressed
        }
        let compressedValue = try await cache.resolve(for: key, codec: compressedCodec) {
            compressed
        }
        let dataResolved = try await cache.resolve(for: key, codec: DataCodec()) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(dataValue == uncompressed)
        #expect(compressedValue.value == compressed)
        #expect(compressedValue.metadata?.codecIdentifier == compressedCodec.identifier)
        #expect(dataResolved.value == uncompressed)
        #expect(dataResolved.metadata?.codecIdentifier == DataCodec().identifier)
        #expect(dataResolved.metadata?.codecIdentifier != compressedValue.metadata?.codecIdentifier)
    }
}

@Test func compressedDataCodecTreatsCorruptionAsMissByDefault() async throws {
    try await withStandardYCache { cache, rootDirectory in
        let key = standardKey("compressed-data-corruption")
        let codec = CompressedDataCodec()
        let original = standardCompressibleHTMLData(repetitions: 24)
        let regenerated = standardCompressibleHTMLData(repetitions: 25)

        _ = try await cache.resolve(for: key, codec: codec) {
            original
        }
        let dataFile = try #require(try storedDataFileURLs(in: rootDirectory).first)
        try Data("not-a-valid-compressed-payload".utf8).write(to: dataFile)

        let newCache = YCache(storageDirectory: rootDirectory)
        let resolved = try await newCache.resolve(for: key, codec: codec) {
            regenerated
        }

        #expect(resolved.value == regenerated)
        #expect(resolved.source == .generated)
    }
}

@Test func compressedDataCodecRejectsInvalidPayloads() throws {
    let codec = CompressedDataCodec()

    #expect(throws: (any Error).self) {
        _ = try codec.decode(Data("not-yashima-compressed-data".utf8))
    }
}

@Test func codableConvenienceRoundTripsJSONAndUsesDefaultFormatIdentity() async throws {
    try await withStandardYCache { cache, rootDirectory in
        let key = standardKey("codable-json")
        let summary = StandardSummary(title: "Yashima", count: 6)

        let generated: StandardSummary = try await cache.codable(for: key) {
            summary
        }
        let explicit: StandardSummary = try await cache.codable(for: key, format: .json) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }
        let resolved = try await cache.resolve(
            for: key,
            codec: CodableCodec<StandardSummary>(format: .json)
        ) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted: StandardSummary = try await newCache.codable(for: key) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(generated == summary)
        #expect(explicit == summary)
        #expect(resolved.value == summary)
        #expect(resolved.source == .memory)
        #expect(persisted == summary)
    }
}

@Test func codableFormatsHaveDistinctIdentifiersAndEntries() async throws {
    try await withStandardYCache { cache, _ in
        let key = standardKey("codable-formats")
        let jsonValue = StandardSummary(title: "json", count: 1)
        let propertyListValue = StandardSummary(title: "plist", count: 2)
        let jsonCodec = CodableCodec<StandardSummary>(format: .json)
        let propertyListCodec = CodableCodec<StandardSummary>(format: .propertyList)

        let json: StandardSummary = try await cache.codable(for: key, format: .json) {
            jsonValue
        }
        let propertyList: StandardSummary = try await cache.codable(
            for: key,
            format: .propertyList
        ) {
            propertyListValue
        }

        let jsonResolved = try await cache.resolve(for: key, codec: jsonCodec) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }
        let propertyListResolved = try await cache.resolve(for: key, codec: propertyListCodec) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(json == jsonValue)
        #expect(propertyList == propertyListValue)
        #expect(jsonResolved.metadata?.codecIdentifier == jsonCodec.identifier)
        #expect(propertyListResolved.metadata?.codecIdentifier == propertyListCodec.identifier)
        #expect(jsonResolved.metadata?.codecIdentifier != propertyListResolved.metadata?.codecIdentifier)
    }
}

@Test func standardCodecIdentifiersDescribeFormatAndType() {
    let typeName = String(reflecting: StandardSummary.self)
    let json = CodableCodec<StandardSummary>(format: .json)
    let propertyList = CodableCodec<StandardSummary>(format: .propertyList)

    #expect(DataCodec().identifier == "data-v1")
    #expect(CompressedDataCodec().identifier == "compressed-data-lzfse-v1")
    #expect(json.identifier == "codable-json-v1:\(typeName)")
    #expect(propertyList.identifier == "codable-property-list-binary-v1:\(typeName)")
    #expect(json.identifier != propertyList.identifier)
}

#if canImport(UIKit) || canImport(AppKit)
@Test func imageCodecIdentifiersIncludeFormatAndJPEGQuality() {
    #expect(ImageCodec.png.identifier == "image-png-v1")
    #expect(ImageCodec.jpeg().identifier == "image-jpeg-q85-v1")
    #expect(ImageCodec.jpeg(quality: 0.85).identifier == "image-jpeg-q85-v1")
    #expect(ImageCodec.jpeg(quality: 0.90).identifier == "image-jpeg-q90-v1")
    #expect(ImageCodec.jpeg(quality: 0.85).identifier != ImageCodec.png.identifier)
}

@Test func imageConveniencesRoundTripAndUseCodecIdentity() async throws {
    try await withStandardYCache { cache, rootDirectory in
        let key = standardKey("image-default-jpeg")
        let defaultJPEG = ImageCodec.jpeg()

        let generated = try await cache.jpeg(for: key) {
            makeStandardTestImage(width: 3, height: 2)
        }
        let resolved = try await cache.resolve(for: key, codec: defaultJPEG) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        let newCache = YCache(storageDirectory: rootDirectory)
        let persisted = try await newCache.resolve(for: key, codec: defaultJPEG) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(imageSize(generated) == .init(width: 3, height: 2))
        #expect(imageSize(resolved.value) == .init(width: 3, height: 2))
        #expect(resolved.source == .memory)
        #expect(resolved.metadata?.cost == 3 * 2 * 4)
        #expect(resolved.metadata?.codecIdentifier == defaultJPEG.identifier)
        #expect(persisted.source == .storage)
        #expect(imageSize(persisted.value) == .init(width: 3, height: 2))
    }
}

@Test func jpegAndPNGUseSeparateEntriesForTheSameKey() async throws {
    try await withStandardYCache { cache, _ in
        let key = standardKey("same-image-key")
        let jpeg = ImageCodec.jpeg(quality: 0.90)
        let png = ImageCodec.png

        _ = try await cache.jpeg(for: key, quality: 0.90) {
            makeStandardTestImage(width: 2, height: 2)
        }
        _ = try await cache.png(for: key) {
            makeStandardTestImage(width: 4, height: 3)
        }

        let jpegResolved = try await cache.resolve(for: key, codec: jpeg) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }
        let pngResolved = try await cache.resolve(for: key, codec: png) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(jpegResolved.metadata?.codecIdentifier == jpeg.identifier)
        #expect(pngResolved.metadata?.codecIdentifier == png.identifier)
        #expect(jpegResolved.metadata?.codecIdentifier != pngResolved.metadata?.codecIdentifier)
        #expect(imageSize(jpegResolved.value) == .init(width: 2, height: 2))
        #expect(imageSize(pngResolved.value) == .init(width: 4, height: 3))
    }
}

@Test func optionalImageConveniencesOnlyCacheNonNilImages() async throws {
    try await withStandardYCache { cache, _ in
        let nilKey = standardKey("optional-jpeg-nil")
        let imageKey = standardKey("optional-png-image")

        let nilImage = try await cache.optionalJPEG(for: nilKey) {
            nil
        }
        let nilCached = try await cache.valueIfCached(for: nilKey, codec: ImageCodec.jpeg())

        let pngImage = try await cache.optionalPNG(for: imageKey) {
            makeStandardTestImage(width: 5, height: 4)
        }
        let pngResolved = try await cache.resolve(for: imageKey, codec: ImageCodec.png) {
            throw StandardConvenienceTestError.unexpectedGenerator
        }

        #expect(nilImage == nil)
        #expect(nilCached == nil)
        #expect(imageSize(pngImage!) == .init(width: 5, height: 4))
        #expect(imageSize(pngResolved.value) == .init(width: 5, height: 4))
        #expect(pngResolved.metadata?.codecIdentifier == ImageCodec.png.identifier)
    }
}

@Test func optionalJPEGConvenienceCoalescesConcurrentMisses() async throws {
    try await withStandardYCache { cache, _ in
        let key = standardKey("optional-jpeg-single-flight")
        let counter = StandardCallCounter()

        let sizes = try await withThrowingTaskGroup(of: StandardImageSize?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let image = try await cache.optionalJPEG(for: key) {
                        _ = await counter.increment()
                        try await Task.sleep(nanoseconds: 100_000_000)
                        return makeStandardTestImage(width: 6, height: 5)
                    }
                    return image.map(imageSize)
                }
            }

            var sizes: [StandardImageSize?] = []
            for try await size in group {
                sizes.append(size)
            }
            return sizes
        }

        let cached = try await cache.valueIfCached(for: key, codec: ImageCodec.jpeg())

        #expect(sizes.count == 12)
        #expect(sizes.allSatisfy { $0 == .init(width: 6, height: 5) })
        #expect(imageSize(cached!) == .init(width: 6, height: 5))
        #expect(await counter.count == 1)
    }
}
#endif

private struct StandardSummary: Codable, Sendable, Equatable {
    var title: String
    var count: Int
}

private enum StandardConvenienceTestError: Error {
    case unexpectedGenerator
}

private struct StandardImageSize: Sendable, Equatable {
    var width: Int
    var height: Int
}

private actor StandardCallCounter {
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

private func withStandardYCache<T>(
    _ operation: (YCache, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaStandardConvenienceTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let cache = YCache(storageDirectory: rootDirectory)

    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    return try await operation(cache, rootDirectory)
}

private func standardKey(_ name: String) -> CacheKey {
    CacheKey(namespace: "standard-convenience-tests", identity: name)
}

private func standardCompressibleHTMLData(repetitions: Int) -> Data {
    let fragment = """
    <section class="markdown-body">
      <h2>Generated Artifact Cache</h2>
      <p>Yashima stores reusable local artifacts with predictable cache keys.</p>
      <pre><code>let value = try await cache.resolve(for: key, codec: codec) { generate() }</code></pre>
    </section>

    """
    let html = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Yashima</title></head><body>
    \(String(repeating: fragment, count: repetitions))
    </body></html>
    """
    return Data(html.utf8)
}

private func storedDataFiles(in rootDirectory: URL) throws -> [Data] {
    try storedDataFileURLs(in: rootDirectory).map {
        try Data(contentsOf: $0)
    }
}

private func storedDataFileURLs(in rootDirectory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
        return []
    }

    let enumerator = FileManager.default.enumerator(
        at: rootDirectory,
        includingPropertiesForKeys: nil
    )
    var urls: [URL] = []
    while let url = enumerator?.nextObject() as? URL {
        if url.pathExtension == "data" {
            urls.append(url)
        }
    }
    return urls.sorted { $0.path < $1.path }
}

#if canImport(UIKit) || canImport(AppKit)
private func makeStandardTestImage(width: Int, height: Int) -> ImageCodec.PlatformImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let pixels = (0..<(width * height)).flatMap { index -> [UInt8] in
        let red = UInt8((index * 53) % 255)
        let green = UInt8((index * 97) % 255)
        let blue = UInt8((index * 193) % 255)
        return [red, green, blue, 255]
    }
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: bytesPerPixel * 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!

    #if canImport(UIKit)
    return UIImage(cgImage: cgImage)
    #elseif canImport(AppKit)
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    #endif
}

private func imageSize(_ image: ImageCodec.PlatformImage) -> StandardImageSize {
    StandardImageSize(
        width: Int(image.size.width.rounded()),
        height: Int(image.size.height.rounded())
    )
}

private func imageSize(_ value: ImageCodec.Value) -> StandardImageSize {
    imageSize(value.image)
}
#endif
