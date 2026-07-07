import Foundation
import SwiftUI
import Yashima

struct TextArtifactsScreen: View {
    @StateObject private var viewModel = TextArtifactsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                documentPicker
                controls
                resultGrid
                payloadPreview
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Text Artifacts")
        .task(id: viewModel.selectedDocumentID) {
            await viewModel.resolve()
        }
    }
}

private extension TextArtifactsScreen {
    var documentPicker: some View {
        Picker("Document", selection: $viewModel.selectedDocumentID) {
            ForEach(viewModel.documents) { document in
                Text(document.shortTitle)
                    .tag(document.id)
            }
        }
        .pickerStyle(.segmented)
    }

    var controls: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.resolve()
                }
            } label: {
                Label("Resolve", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)

            Button {
                viewModel.useFreshCacheInstance()
                Task {
                    await viewModel.resolve()
                }
            } label: {
                Label("New Cache", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isWorking)

            Button {
                Task {
                    await viewModel.resolve(forceRefresh: true)
                }
            } label: {
                Label("Refresh", systemImage: "wand.and.sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isWorking)
        }
        .labelStyle(.iconOnly)
    }

    var resultGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
            TextArtifactResultCard(result: viewModel.metadataResult)
            TextArtifactResultCard(result: viewModel.payloadResult)
        }
    }

    var payloadPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.selectedDocument.title)
                    .font(.headline)

                Spacer()

                if viewModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text(viewModel.payloadPreview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct TextArtifactResultCard: View {
    let result: TextArtifactResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(result?.title ?? "Pending")
                    .font(.headline)

                Spacer()

                if let source = result?.source {
                    Label(source.label, systemImage: Optional(source).systemImageName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Optional(source).tint)
                } else {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(result?.summary ?? "Resolve this document to inspect the cached artifact.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(result?.codecIdentifier ?? "-")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Label(result?.byteCountText ?? "-", systemImage: "shippingbox")
                    Spacer()
                    Label(result?.elapsedText ?? "-", systemImage: "timer")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
final class TextArtifactsViewModel: ObservableObject {
    @Published var selectedDocumentID = TextDocumentFixture.samples[0].id
    @Published private(set) var metadataResult: TextArtifactResult?
    @Published private(set) var payloadResult: TextArtifactResult?
    @Published private(set) var payloadPreview = "Resolving a document produces Codable metadata and a compressed text payload."
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    let documents = TextDocumentFixture.samples

    private var cache = TextArtifactsViewModel.makeCache()
    private let metadataCodec = CodableCodec<TextArtifactMetadata>(format: .json)
    private let payloadCodec = CompressedDataCodec()

    var selectedDocument: TextDocumentFixture {
        documents.first { $0.id == selectedDocumentID } ?? documents[0]
    }

    func resolve(forceRefresh: Bool = false) async {
        let document = selectedDocument
        isWorking = true
        errorMessage = nil

        var options = YCache.Options.default
        if forceRefresh {
            options.lookupPolicy = .refresh
        }

        do {
            let metadataStartedAt = ContinuousClock.now
            let metadataResolved = try await cache.resolve(
                for: document.metadataKey,
                codec: metadataCodec,
                options: options
            ) {
                try await TextArtifactGenerator.makeMetadata(for: document)
            }
            let metadataDuration = metadataStartedAt.duration(to: ContinuousClock.now)

            let payloadStartedAt = ContinuousClock.now
            let payloadResolved = try await cache.resolve(
                for: document.payloadKey,
                codec: payloadCodec,
                options: options
            ) {
                try await TextArtifactGenerator.renderPayload(for: document)
            }
            let payloadDuration = payloadStartedAt.duration(to: ContinuousClock.now)

            metadataResult = TextArtifactResult(
                id: "metadata",
                title: "Codable metadata",
                source: metadataResolved.source,
                summary: metadataResolved.value.summary,
                codecIdentifier: metadataCodec.identifier,
                byteCount: metadataResolved.metadata?.byteCount,
                duration: metadataDuration
            )
            payloadResult = TextArtifactResult(
                id: "payload",
                title: "Compressed payload",
                source: payloadResolved.source,
                summary: "\(payloadResolved.value.count.formatted()) rendered bytes before compression",
                codecIdentifier: payloadCodec.identifier,
                byteCount: payloadResolved.metadata?.byteCount,
                duration: payloadDuration
            )
            payloadPreview = String(decoding: payloadResolved.value.prefix(780), as: UTF8.self)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }

        isWorking = false
    }

    func useFreshCacheInstance() {
        cache = Self.makeCache()
        metadataResult = nil
        payloadResult = nil
    }
}

private extension TextArtifactsViewModel {
    static func makeCache() -> YCache {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "YashimaPreviewLab", directoryHint: .isDirectory)
            .appending(path: "TextArtifacts", directoryHint: .isDirectory)

        return YCache(
            storageDirectory: root,
            memoryMaximumEntryCount: 8
        )
    }
}

struct TextArtifactResult: Identifiable {
    let id: String
    let title: String
    let source: YCache.Source
    let summary: String
    let codecIdentifier: String
    let byteCount: Int?
    let duration: Duration

    var byteCountText: String {
        byteCount?.formatted() ?? "pending"
    }

    var elapsedText: String {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000

        if milliseconds < 10 {
            return String(format: "%.1f ms", milliseconds)
        }

        return "\(Int(milliseconds.rounded())) ms"
    }
}

struct TextDocumentFixture: Identifiable, Hashable, Sendable {
    let id: String
    let shortTitle: String
    let title: String
    let revision: Int
    let sections: [TextDocumentSection]

    var metadataKey: CacheKey {
        CacheKey(namespace: "preview-lab-document-metadata", identity: id)
            .variant("content-revision", revision.formatted())
            .version("metadata-schema", 1)
    }

    var payloadKey: CacheKey {
        CacheKey(namespace: "preview-lab-document-payloads", identity: id)
            .variant("content-revision", revision.formatted())
            .variant("format", "markdown-preview")
            .version("renderer", 1)
    }

    var wordCount: Int {
        sections
            .flatMap(\.paragraphs)
            .flatMap { $0.split(separator: " ") }
            .count
    }

    static let samples = [
        TextDocumentFixture(
            id: "offline-guide",
            shortTitle: "Guide",
            title: "Offline Preview Guide",
            revision: 4,
            sections: [
                TextDocumentSection(
                    heading: "First Paint",
                    paragraphs: [
                        "The app renders a compact first-paint payload for documents that may be opened repeatedly.",
                        "The payload is disposable because the authoritative document can render it again."
                    ]
                ),
                TextDocumentSection(
                    heading: "Cache Boundary",
                    paragraphs: [
                        "The document list, permissions, and original text stay outside Yashima.",
                        "Yashima stores only the generated preview artifact and the derived metadata."
                    ]
                )
            ]
        ),
        TextDocumentFixture(
            id: "search-artifact",
            shortTitle: "Search",
            title: "Search Artifact Snapshot",
            revision: 7,
            sections: [
                TextDocumentSection(
                    heading: "Candidate Snapshot",
                    paragraphs: [
                        "A search feature can build a small artifact from the readable documents available at query time.",
                        "The cache key includes the candidate identity and the normalizer version."
                    ]
                ),
                TextDocumentSection(
                    heading: "Authoritative Data",
                    paragraphs: [
                        "The cached artifact is not the search index source of truth.",
                        "If the document set changes, the app changes the key and regenerates the artifact."
                    ]
                )
            ]
        ),
        TextDocumentFixture(
            id: "summary-payload",
            shortTitle: "Summary",
            title: "Generated Summary Payload",
            revision: 2,
            sections: [
                TextDocumentSection(
                    heading: "Reusable Summary",
                    paragraphs: [
                        "Summaries, manifests, and rendered text payloads are often text-like data that compresses well.",
                        "A compressed codec keeps this choice explicit and gives it a different cache identity."
                    ]
                ),
                TextDocumentSection(
                    heading: "Regeneration",
                    paragraphs: [
                        "The app can safely regenerate this payload from local inputs.",
                        "Yashima simply prevents the same local work from being repeated on every return visit."
                    ]
                )
            ]
        )
    ]
}

struct TextDocumentSection: Hashable, Sendable {
    let heading: String
    let paragraphs: [String]
}

struct TextArtifactMetadata: Codable, Sendable {
    let title: String
    let revision: Int
    let sectionCount: Int
    let wordCount: Int
    let summary: String
}

enum TextArtifactGenerator {
    static func makeMetadata(for document: TextDocumentFixture) async throws -> TextArtifactMetadata {
        try await Task.sleep(for: .milliseconds(60))
        try Task.checkCancellation()

        return TextArtifactMetadata(
            title: document.title,
            revision: document.revision,
            sectionCount: document.sections.count,
            wordCount: document.wordCount,
            summary: "\(document.sections.count) sections, \(document.wordCount) words, revision \(document.revision)"
        )
    }

    static func renderPayload(for document: TextDocumentFixture) async throws -> Data {
        try await Task.sleep(for: .milliseconds(95))
        try Task.checkCancellation()

        var lines = [
            "# \(document.title)",
            "",
            "revision: \(document.revision)",
            "artifact-kind: markdown-preview",
            ""
        ]

        for section in document.sections {
            lines.append("## \(section.heading)")
            lines.append("")
            for paragraph in section.paragraphs {
                lines.append(paragraph)
                lines.append("")
            }
        }

        lines.append("This generated payload is synthetic sample data for YashimaPreviewLab.")
        return Data(lines.joined(separator: "\n").utf8)
    }
}

#Preview {
    NavigationStack {
        TextArtifactsScreen()
    }
}
