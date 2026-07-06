import Foundation
import Testing
import Yashima

@Test func readmeBasicUsageExamplesRoundTripGeneratedArtifacts() async throws {
    try await withDocumentationCache { cache, rootDirectory in
        let thumbnailKey = CacheKey("thumbnail-photo-42", namespace: "thumbnails")
        let summaryKey = CacheKey("summary-report-7", namespace: "summaries")
        let thumbnailData = Data([0x59, 0x41, 0x53, 0x48])
        let summary = DocumentationSummary(title: "Yashima", count: 3)

        let thumbnail = try await cache.data(for: thumbnailKey) {
            thumbnailData
        }
        let generatedSummary: DocumentationSummary = try await cache.codable(for: summaryKey) {
            summary
        }

        let coldCache = YCache(storageDirectory: rootDirectory)
        let cachedThumbnail = try await coldCache.data(for: thumbnailKey) {
            throw DocumentationExampleError.unexpectedGeneration
        }
        let cachedSummary: DocumentationSummary = try await coldCache.codable(for: summaryKey) {
            throw DocumentationExampleError.unexpectedGeneration
        }

        #expect(thumbnail == thumbnailData)
        #expect(generatedSummary == summary)
        #expect(cachedThumbnail == thumbnailData)
        #expect(cachedSummary == summary)
    }
}

@Test func readmeCodecBasedCoreExampleReportsSourcesAndPeeksMemory() async throws {
    try await withDocumentationCache { cache, rootDirectory in
        let key = CacheKey(namespace: "reports", identity: "weekly")
            .variant("locale", "en-US")
            .version("renderer", 1)
        let reports = cache.using(DocumentationReportCodec())

        let first = try await reports.resolve(for: key) {
            DocumentationReport(body: "generated")
        }
        let immediate = try await reports.peek(for: key)

        let coldReports = YCache(storageDirectory: rootDirectory)
            .using(DocumentationReportCodec())
        let persisted = try await coldReports.resolve(for: key) {
            throw DocumentationExampleError.unexpectedGeneration
        }

        #expect(first.value.body == "generated")
        #expect(first.source == .generated)
        #expect(immediate?.body == "generated")
        #expect(persisted.value.body == "generated")
        #expect(persisted.source == .storage)
    }
}

@Test func readmeCompressedDataExampleUsesExplicitCodec() async throws {
    try await withDocumentationCache { cache, rootDirectory in
        let key = CacheKey(namespace: "rendered-documents", identity: "intro")
            .variant("format", "html")
            .version("renderer", 1)
        let documents = cache.using(CompressedDataCodec())
        let renderedHTML = "<main><h1>Yashima</h1><p>Generated artifact cache.</p></main>"
        let htmlData = Data(renderedHTML.utf8)

        let generated = try await documents.value(for: key) {
            htmlData
        }
        let cached = try await YCache(storageDirectory: rootDirectory)
            .using(CompressedDataCodec())
            .value(for: key) {
                throw DocumentationExampleError.unexpectedGeneration
            }

        #expect(generated == htmlData)
        #expect(cached == htmlData)
    }
}

@Test func readmeLifecycleExamplesUsePublicLookupAndRemovalAPIs() async throws {
    try await withDocumentationCache { cache, _ in
        let key = CacheKey(namespace: "thumbnails", identity: "asset-9")
        let codec = DataCodec()

        try await cache.store(Data("cached".utf8), for: key, codec: codec)

        let metadata = try await cache.metadata(for: key, codec: codec)
        let isCached = try await cache.contains(for: key, codec: codec)
        let removed = try await cache.remove(for: key, codec: codec)
        let isCachedAfterRemoval = try await cache.contains(for: key, codec: codec)

        #expect(metadata?.codecIdentifier == codec.identifier)
        #expect(isCached)
        #expect(removed)
        #expect(!isCachedAfterRemoval)
    }
}

private struct DocumentationSummary: Codable, Sendable, Equatable {
    var title: String
    var count: Int
}

private struct DocumentationReport: Sendable, Equatable {
    var body: String
}

private struct DocumentationReportCodec: CacheCodec {
    let identifier = "documentation-report-v1"

    func encode(_ value: DocumentationReport) throws -> Data {
        Data(value.body.utf8)
    }

    func decode(_ data: Data) throws -> DocumentationReport {
        guard let body = String(data: data, encoding: .utf8) else {
            throw DocumentationExampleError.invalidUTF8
        }
        return DocumentationReport(body: body)
    }
}

private enum DocumentationExampleError: Error {
    case invalidUTF8
    case unexpectedGeneration
}

private func withDocumentationCache<T>(
    _ operation: (YCache, URL) async throws -> T
) async throws -> T {
    let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "YashimaDocumentationExampleTests-\(UUID().uuidString)",
        isDirectory: true
    )
    let cache = YCache(storageDirectory: rootDirectory)

    defer {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    return try await operation(cache, rootDirectory)
}
