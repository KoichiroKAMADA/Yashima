import SwiftUI
import UIKit
import Yashima

struct ScrollingThumbnailsScreen: View {
    @StateObject private var viewModel = ScrollingThumbnailsViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 148, maximum: 210), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metricStrip
                controls

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.items) { item in
                        ThumbnailTileView(
                            item: item,
                            state: viewModel.state(for: item)
                        )
                        .task(id: viewModel.taskID(for: item)) {
                            await viewModel.load(item)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Scrolling Thumbnails")
    }
}

private extension ScrollingThumbnailsScreen {
    var metricStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
            ThumbnailMetricTile(title: "Generated", value: viewModel.generatedCount, color: .orange)
            ThumbnailMetricTile(title: "Memory", value: viewModel.memoryHitCount, color: .blue)
            ThumbnailMetricTile(title: "Storage", value: viewModel.storageHitCount, color: .green)
            ThumbnailMetricTile(title: "Cancelled", value: viewModel.cancelledCount, color: .secondary)
        }
    }

    var controls: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.resetCounters()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.useFreshCacheInstance()
            } label: {
                Label("New Cache", systemImage: "internaldrive")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                Task {
                    await viewModel.clearStoredThumbnails()
                }
            } label: {
                Label("Clear", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.iconOnly)
    }
}

private struct ThumbnailTileView: View {
    let item: ThumbnailFixture
    let state: ThumbnailLoadState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1.36, contentMode: .fit)

                if let image = state.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: item.systemImageName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                sourceBadge
                    .padding(7)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(state.accessibilityText)")
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch state.phase {
        case .idle:
            Image(systemName: "circle.dashed")
                .thumbnailBadgeStyle(color: .secondary)
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .padding(7)
                .background(.regularMaterial, in: Capsule())
        case .loaded(let source):
            Label(source.label, systemImage: Optional(source).systemImageName)
                .thumbnailBadgeStyle(color: Optional(source).tint)
        case .cancelled:
            Image(systemName: "xmark")
                .thumbnailBadgeStyle(color: .secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .thumbnailBadgeStyle(color: .red)
        }
    }
}

private struct ThumbnailMetricTile: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ThumbnailBadgeModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .labelStyle(.iconOnly)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

private extension View {
    func thumbnailBadgeStyle(color: Color) -> some View {
        modifier(ThumbnailBadgeModifier(color: color))
    }
}

@MainActor
final class ScrollingThumbnailsViewModel: ObservableObject {
    @Published private(set) var generatedCount = 0
    @Published private(set) var memoryHitCount = 0
    @Published private(set) var storageHitCount = 0
    @Published private(set) var cancelledCount = 0
    @Published private(set) var failedCount = 0
    @Published private(set) var reloadGeneration = 0

    let items = ThumbnailFixture.samples

    private var states: [ThumbnailFixture.ID: ThumbnailLoadState] = [:]
    private var cache = ScrollingThumbnailsViewModel.makeCache()
    private let codec = ImageCodec.jpeg(quality: 0.82)

    func state(for item: ThumbnailFixture) -> ThumbnailLoadState {
        states[item.id] ?? ThumbnailLoadState()
    }

    func taskID(for item: ThumbnailFixture) -> String {
        "\(item.id)-\(reloadGeneration)"
    }

    func load(_ item: ThumbnailFixture) async {
        states[item.id] = state(for: item).loading()
        objectWillChange.send()

        var options = YCache.Options.uiLifecycle
        options.cost = .units(1)

        do {
            let resolved = try await cache.resolve(
                for: item.cacheKey,
                codec: codec,
                options: options
            ) {
                ImageCodec.Value(try await SyntheticThumbnailRenderer.render(item))
            }

            states[item.id] = ThumbnailLoadState(
                image: resolved.value.image,
                phase: .loaded(resolved.source)
            )
            record(resolved.source)
            objectWillChange.send()
        } catch is CancellationError {
            states[item.id] = ThumbnailLoadState(phase: .cancelled)
            cancelledCount += 1
            objectWillChange.send()
        } catch {
            states[item.id] = ThumbnailLoadState(phase: .failed)
            failedCount += 1
            objectWillChange.send()
        }
    }

    func resetCounters() {
        generatedCount = 0
        memoryHitCount = 0
        storageHitCount = 0
        cancelledCount = 0
        failedCount = 0
    }

    func useFreshCacheInstance() {
        cache = Self.makeCache()
        states = [:]
        reloadGeneration += 1
    }

    func clearStoredThumbnails() async {
        do {
            try await cache.removeAll(in: ThumbnailFixture.namespace)
            cache = Self.makeCache()
            states = [:]
            resetCounters()
            reloadGeneration += 1
        } catch {
            failedCount += 1
        }
    }
}

private extension ScrollingThumbnailsViewModel {
    static func makeCache() -> YCache {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "YashimaPreviewLab", directoryHint: .isDirectory)
            .appending(path: "ScrollingThumbnails", directoryHint: .isDirectory)

        return YCache(
            storageDirectory: root,
            memoryMaximumEntryCount: 18
        )
    }

    func record(_ source: YCache.Source) {
        switch source {
        case .generated:
            generatedCount += 1
        case .memory:
            memoryHitCount += 1
        case .storage:
            storageHitCount += 1
        }
    }
}

struct ThumbnailFixture: Identifiable, Hashable, Sendable {
    static let namespace = "preview-lab-thumbnails"

    let id: String
    let title: String
    let subtitle: String
    let systemImageName: String
    let hue: Double
    let rendererRevision: Int

    var cacheKey: CacheKey {
        CacheKey(namespace: Self.namespace, identity: id)
            .variant("symbol", systemImageName)
            .variant("size", "320x236")
            .variant("hue", String(format: "%.3f", hue))
            .version("synthetic-thumbnail-renderer", rendererRevision)
    }

    static let samples: [ThumbnailFixture] = {
        let symbols = [
            "photo", "map", "chart.xyaxis.line", "waveform", "doc.text",
            "film", "paintpalette", "sparkles", "camera.filters", "square.grid.3x3",
            "rectangle.stack", "timeline.selection", "slider.horizontal.3", "point.3.connected.trianglepath.dotted", "shippingbox"
        ]

        return (1...84).map { index in
            ThumbnailFixture(
                id: "synthetic-thumbnail-\(index)",
                title: "Artifact \(index)",
                subtitle: index.isMultiple(of: 3) ? "scroll cell" : "generated preview",
                systemImageName: symbols[(index - 1) % symbols.count],
                hue: Double((index * 37) % 360) / 360.0,
                rendererRevision: 1
            )
        }
    }()
}

struct ThumbnailLoadState {
    var image: UIImage?
    var phase: ThumbnailPhase = .idle

    func loading() -> ThumbnailLoadState {
        ThumbnailLoadState(image: image, phase: .loading)
    }

    var accessibilityText: String {
        switch phase {
        case .idle:
            return "not loaded"
        case .loading:
            return "loading"
        case .loaded(let source):
            return source.label
        case .cancelled:
            return "cancelled"
        case .failed:
            return "failed"
        }
    }
}

enum ThumbnailPhase: Sendable {
    case idle
    case loading
    case loaded(YCache.Source)
    case cancelled
    case failed
}

@MainActor
enum SyntheticThumbnailRenderer {
    static func render(_ item: ThumbnailFixture) async throws -> UIImage {
        for step in 0..<4 {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(18 + step * 7))
        }

        let size = CGSize(width: 320, height: 236)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let base = UIColor(
                hue: item.hue,
                saturation: 0.62,
                brightness: 0.88,
                alpha: 1
            )
            let second = UIColor(
                hue: fmod(item.hue + 0.13, 1),
                saturation: 0.54,
                brightness: 0.58,
                alpha: 1
            )

            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [base.cgColor, second.cgColor] as CFArray,
                locations: [0, 1]
            )

            cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: CGPoint(x: rect.maxX, y: rect.maxY),
                options: []
            )

            UIColor.white.withAlphaComponent(0.16).setFill()
            UIBezierPath(ovalIn: CGRect(x: -46, y: -38, width: 150, height: 150)).fill()
            UIBezierPath(ovalIn: CGRect(x: 220, y: 124, width: 130, height: 130)).fill()

            drawSymbol(item.systemImageName, in: rect)
            drawCaption(item.title, subtitle: item.subtitle, in: rect)
        }
    }

    private static func drawSymbol(_ name: String, in rect: CGRect) {
        guard let image = UIImage(systemName: name) else {
            return
        }

        let configuration = UIImage.SymbolConfiguration(pointSize: 58, weight: .bold)
        let symbol = image.withConfiguration(configuration).withTintColor(.white, renderingMode: .alwaysOriginal)
        let symbolSize = CGSize(width: 86, height: 86)
        symbol.draw(in: CGRect(
            x: rect.midX - symbolSize.width / 2,
            y: rect.midY - symbolSize.height / 2 - 10,
            width: symbolSize.width,
            height: symbolSize.height
        ))
    }

    private static func drawCaption(_ title: String, subtitle: String, in rect: CGRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.78),
        ]

        title.draw(
            in: CGRect(x: 18, y: rect.maxY - 58, width: rect.width - 36, height: 28),
            withAttributes: titleAttributes
        )
        subtitle.draw(
            in: CGRect(x: 18, y: rect.maxY - 30, width: rect.width - 36, height: 18),
            withAttributes: subtitleAttributes
        )
    }
}

#Preview {
    NavigationStack {
        ScrollingThumbnailsScreen()
    }
}
