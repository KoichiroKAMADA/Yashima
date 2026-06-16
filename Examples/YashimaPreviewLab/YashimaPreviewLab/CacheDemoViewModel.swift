import Foundation
import UIKit
import Yashima

@MainActor
final class CacheDemoViewModel: ObservableObject {
    @Published private(set) var recipes = ArtifactRecipe.samples
    @Published private(set) var selectedRecipe = ArtifactRecipe.samples[0]
    @Published private(set) var image: UIImage?
    @Published private(set) var source: YCache.Source?
    @Published private(set) var elapsedText = "-"
    @Published private(set) var benchmarkRows = BenchmarkRow.defaults(for: ArtifactRecipe.samples[0])
    @Published private(set) var detailRows: [DetailRow] = []
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private var cache = CacheDemoViewModel.makeCache()
    private let codec = ImageCodec.jpeg(quality: 0.85)

    func select(_ recipe: ArtifactRecipe) {
        selectedRecipe = recipe
        image = nil
        source = nil
        elapsedText = "-"
        benchmarkRows = BenchmarkRow.defaults(for: recipe)
        detailRows = []
        errorMessage = nil
    }

    func runBenchmark() async {
        let recipe = selectedRecipe

        isWorking = true
        errorMessage = nil
        image = nil
        source = nil
        elapsedText = "-"
        detailRows = []
        benchmarkRows = BenchmarkRow.defaults(for: recipe)

        do {
            // Force generation once so the benchmark shows the real cost of
            // producing the artifact before any cache can help.
            try await run(
                step: .generate,
                recipe: recipe,
                attempts: 1,
                lookupPolicy: .refresh
            ) {
                cache
            }
            // Reuse the same YCache instance to demonstrate the in-memory layer.
            try await run(
                step: .memory,
                recipe: recipe,
                attempts: 5,
                lookupPolicy: .normal
            ) {
                cache
            }
            // Use fresh YCache instances with the same storage directory to
            // demonstrate recovery from the persistent disk layer.
            try await run(
                step: .storage,
                recipe: recipe,
                attempts: 5,
                lookupPolicy: .normal
            ) {
                CacheDemoViewModel.makeCache()
            }

            cache = CacheDemoViewModel.makeCache()
        } catch {
            errorMessage = String(describing: error)
            markRunningRowAsFailed()
        }

        isWorking = false
    }
}

extension CacheDemoViewModel {
    enum BenchmarkStep: String, CaseIterable, Sendable {
        case generate
        case memory
        case storage

        var title: String {
            switch self {
            case .generate:
                return "Generate"
            case .memory:
                return "Memory hit"
            case .storage:
                return "Disk hit"
            }
        }

        func subtitle(for recipe: ArtifactRecipe) -> String {
            switch self {
            case .generate:
                return recipe.generationLabel
            case .memory:
                return "Same cache x5"
            case .storage:
                return "New cache x5"
            }
        }
    }

    struct BenchmarkRow: Identifiable, Sendable {
        let step: BenchmarkStep
        let subtitle: String
        var state: BenchmarkState
        var source: YCache.Source?
        var elapsedText: String
        var byteCountText: String

        var id: BenchmarkStep {
            step
        }

        static func defaults(for recipe: ArtifactRecipe) -> [BenchmarkRow] {
            BenchmarkStep.allCases.map {
                BenchmarkRow(
                    step: $0,
                    subtitle: $0.subtitle(for: recipe),
                    state: .waiting,
                    source: nil,
                    elapsedText: "-",
                    byteCountText: "-"
                )
            }
        }
    }

    enum BenchmarkState: Sendable {
        case waiting
        case running
        case completed
        case failed
    }

    struct DetailRow: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let value: String
    }
}

private extension CacheDemoViewModel {
    static func makeCache() -> YCache {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "YashimaPreviewLab", directoryHint: .isDirectory)

        // A real app would usually keep one YCache around for a feature or app
        // subsystem and point it at an app-owned cache directory.
        return YCache(
            storageDirectory: root,
            memoryMaximumEntryCount: 4
        )
    }

    func run(
        step: BenchmarkStep,
        recipe: ArtifactRecipe,
        attempts: Int,
        lookupPolicy: CacheLookupPolicy,
        _ makeCacheForAttempt: () -> YCache
    ) async throws {
        updateBenchmarkRow(step: step) { row in
            row.state = .running
            row.source = nil
            row.elapsedText = "Running"
            row.byteCountText = "-"
        }

        var bestMeasurement: BenchmarkMeasurement?

        for _ in 0..<max(1, attempts) {
            let measurement = try await measure(
                recipe: recipe,
                cache: makeCacheForAttempt(),
                lookupPolicy: lookupPolicy
            )

            if bestMeasurement == nil || measurement.elapsedMilliseconds < bestMeasurement!.elapsedMilliseconds {
                bestMeasurement = measurement
            }
        }

        guard let bestMeasurement else {
            return
        }

        image = bestMeasurement.resolved.value.image
        source = bestMeasurement.resolved.source
        elapsedText = bestMeasurement.elapsedText
        detailRows = makeDetailRows(for: bestMeasurement.resolved, recipe: recipe)

        updateBenchmarkRow(step: step) { row in
            row.state = .completed
            row.source = bestMeasurement.resolved.source
            row.elapsedText = bestMeasurement.elapsedText
            row.byteCountText = bestMeasurement.resolved.metadata?.byteCount.formatted() ?? "-"
        }
    }

    func measure(
        recipe: ArtifactRecipe,
        cache: YCache,
        lookupPolicy: CacheLookupPolicy
    ) async throws -> BenchmarkMeasurement {
        let startedAt = ContinuousClock.now
        var options = YCache.Options(cost: .units(1))
        options.lookupPolicy = lookupPolicy

        // This is the core Yashima usage pattern:
        // ask for a value by CacheKey + CacheCodec, and provide the expensive
        // generator closure that should run only on a miss or explicit refresh.
        let resolved = try await cache.resolve(
            for: recipe.cacheKey,
            codec: codec,
            options: options
        ) {
            try await ArtifactGenerator.render(recipe)
        }

        let duration = startedAt.duration(to: ContinuousClock.now)
        return BenchmarkMeasurement(resolved: resolved, duration: duration)
    }

    func makeDetailRows(
        for resolved: YCache.Resolved<ImageCodec.Value>,
        recipe: ArtifactRecipe
    ) -> [DetailRow] {
        var rows = [
            DetailRow(title: "Artifact", value: recipe.title),
            DetailRow(title: "Kind", value: recipe.kindTitle),
            DetailRow(title: "Generator", value: recipe.generationLabel),
            DetailRow(title: "Cache key", value: recipe.cacheKey.identity),
            DetailRow(title: "Codec", value: codec.identifier),
            DetailRow(title: "Source", value: resolved.source.label),
            DetailRow(title: "Shared generation", value: resolved.wasSharedGeneration ? "Yes" : "No"),
        ]

        rows.append(contentsOf: recipe.detailRows)

        if let metadata = resolved.metadata {
            rows.append(DetailRow(title: "Stored bytes", value: metadata.byteCount.formatted()))
            rows.append(DetailRow(title: "Created", value: metadata.createdAt.formatted(date: .omitted, time: .standard)))
            rows.append(DetailRow(title: "Last accessed", value: metadata.lastAccessedAt.formatted(date: .omitted, time: .standard)))
        } else {
            rows.append(DetailRow(title: "Stored bytes", value: "Pending write"))
        }

        return rows
    }

    func updateBenchmarkRow(
        step: BenchmarkStep,
        update: (inout BenchmarkRow) -> Void
    ) {
        guard let index = benchmarkRows.firstIndex(where: { $0.step == step }) else {
            return
        }

        update(&benchmarkRows[index])
    }

    func markRunningRowAsFailed() {
        guard let index = benchmarkRows.firstIndex(where: { $0.state == .running }) else {
            return
        }

        benchmarkRows[index].state = .failed
        benchmarkRows[index].elapsedText = "Failed"
    }
}

private extension ArtifactRecipe {
    var detailRows: [CacheDemoViewModel.DetailRow] {
        switch spec {
        case .map(let spec):
            return [
                CacheDemoViewModel.DetailRow(title: "Route basis", value: spec.routeDescription),
                CacheDemoViewModel.DetailRow(title: "Original GPX points", value: spec.sourcePointCount.formatted()),
                CacheDemoViewModel.DetailRow(title: "Displayed points", value: spec.routePointCount.formatted()),
                CacheDemoViewModel.DetailRow(title: "Route distance", value: String(format: "%.1f km", spec.distanceKilometers)),
                CacheDemoViewModel.DetailRow(title: "Center", value: spec.center.displayString),
                CacheDemoViewModel.DetailRow(title: "Region", value: "\(Int(spec.latitudeMeters)) x \(Int(spec.longitudeMeters)) m"),
            ]
        case .chart(let spec):
            return [
                CacheDemoViewModel.DetailRow(title: "Samples", value: spec.sampleCount.formatted()),
                CacheDemoViewModel.DetailRow(title: "Series", value: "Generate / Storage / Memory"),
                CacheDemoViewModel.DetailRow(title: "Values", value: "Random on each refresh"),
                CacheDemoViewModel.DetailRow(title: "Budget line", value: "\(Int(spec.budgetMilliseconds)) ms"),
            ]
        case .report(let spec):
            return [
                CacheDemoViewModel.DetailRow(title: "Metrics", value: spec.metricTitles.count.formatted()),
                CacheDemoViewModel.DetailRow(title: "Checklist items", value: spec.checklist.count.formatted()),
                CacheDemoViewModel.DetailRow(title: "Ticket tiles", value: spec.tileCount.formatted()),
                CacheDemoViewModel.DetailRow(title: "Values", value: "Random on each refresh"),
            ]
        }
    }
}

private struct BenchmarkMeasurement {
    var resolved: YCache.Resolved<ImageCodec.Value>
    var duration: Duration

    var elapsedMilliseconds: Double {
        duration.milliseconds
    }

    var elapsedText: String {
        duration.formattedForPreviewLab
    }
}

extension YCache.Source {
    var label: String {
        switch self {
        case .generated:
            return "Generated"
        case .memory:
            return "Memory"
        case .storage:
            return "Storage"
        }
    }
}

private extension Duration {
    var formattedForPreviewLab: String {
        if milliseconds < 10 {
            return String(format: "%.1f ms", milliseconds)
        }

        return "\(Int(milliseconds.rounded())) ms"
    }

    var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
