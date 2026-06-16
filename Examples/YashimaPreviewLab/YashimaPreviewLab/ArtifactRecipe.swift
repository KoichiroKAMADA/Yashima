import Foundation
import Yashima

struct ArtifactRecipe: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let subtitle: String
    let systemImageName: String
    let spec: ArtifactSpec

    var cacheKey: CacheKey {
        // Keep the key tied to the artifact's semantic identity and every input
        // that can change the generated image. The codec identifier is added by
        // Yashima, so PNG and JPEG variants never collide.
        var key = CacheKey(namespace: "yashima-preview-lab", identity: id)
            .variant("kind", spec.kindComponent)
            .variant("size", "960x540")
            .version("preview-artifact", 3)

        for component in spec.cacheComponents {
            key = key.variant(component.name, component.value)
        }

        return key
    }

    var kindTitle: String {
        spec.kindTitle
    }

    var generationLabel: String {
        spec.generationLabel
    }

    static let samples: [ArtifactRecipe] = [
        ArtifactRecipe(
            id: "goshikidai-to-yashima-map",
            title: "Goshikidai to Yashima",
            shortTitle: "Map",
            subtitle: "MapKit snapshot from a sanitized 9,426-point route",
            systemImageName: "map",
            spec: .map(
                MapSnapshotSpec(
                    center: MapCoordinate(latitude: 34.3475, longitude: 134.0054),
                    latitudeMeters: 18_500,
                    longitudeMeters: 35_500,
                    routeResourceName: "GoshikidaiToYashimaRoute",
                    routePointCount: 9_426,
                    sourcePointCount: 9_426,
                    distanceKilometers: 104.1,
                    routeDescription: "Trimmed coordinate route, metadata stripped",
                    accentColor: ArtifactColor(red: 0.11, green: 0.48, blue: 0.92)
                )
            )
        ),
        ArtifactRecipe(
            id: "render-cost-chart",
            title: "Render Cost Chart",
            shortTitle: "Chart",
            subtitle: "Swift Charts snapshot for generated metrics",
            systemImageName: "chart.xyaxis.line",
            spec: .chart(
                ChartSnapshotSpec(
                    title: "Generated Preview Cost",
                    subtitle: "Fresh random values are rendered on every generation",
                    sampleCount: 8,
                    budgetMilliseconds: 120,
                    accentColor: ArtifactColor(red: 0.95, green: 0.38, blue: 0.14),
                    storageColor: ArtifactColor(red: 0.16, green: 0.63, blue: 0.37),
                    memoryColor: ArtifactColor(red: 0.11, green: 0.48, blue: 0.92)
                )
            )
        ),
        ArtifactRecipe(
            id: "route-insight-card",
            title: "Route Cache Ticket",
            shortTitle: "Ticket",
            subtitle: "SwiftUI ticket-style manifest rendered into a JPEG",
            systemImageName: "ticket",
            spec: .report(
                ReportSnapshotSpec(
                    title: "Preview Cache Ticket",
                    subtitle: "A SwiftUI-only manifest for a generated route artifact",
                    routeCaption: "Goshikidai -> Yashima",
                    metricTitles: ["Points", "Seed", "Batch"],
                    checklist: [
                        "Generate once",
                        "Store encoded artifact",
                        "Replay without rendering",
                        "Keep key and codec identity"
                    ],
                    tileCount: 9,
                    accentColor: ArtifactColor(red: 0.31, green: 0.25, blue: 0.58),
                    stampColor: ArtifactColor(red: 0.74, green: 0.15, blue: 0.11)
                )
            )
        ),
    ]

}

enum ArtifactSpec: Hashable, Sendable {
    case map(MapSnapshotSpec)
    case chart(ChartSnapshotSpec)
    case report(ReportSnapshotSpec)

    var kindComponent: String {
        switch self {
        case .map:
            return "map-snapshot"
        case .chart:
            return "chart-snapshot"
        case .report:
            return "swiftui-report-card"
        }
    }

    var kindTitle: String {
        switch self {
        case .map:
            return "MapKit Snapshot"
        case .chart:
            return "Swift Charts Snapshot"
        case .report:
            return "SwiftUI Ticket Snapshot"
        }
    }

    var generationLabel: String {
        switch self {
        case .map:
            return "MKMapSnapshotter"
        case .chart:
            return "Swift Charts render"
        case .report:
            return "SwiftUI ImageRenderer"
        }
    }

    var cacheComponents: [CacheKeyComponent] {
        switch self {
        case .map(let spec):
            return [
                CacheKeyComponent("center", spec.center.cacheComponent),
                CacheKeyComponent("region", "\(Int(spec.latitudeMeters))x\(Int(spec.longitudeMeters))"),
                CacheKeyComponent("route-resource", spec.routeResourceName),
                CacheKeyComponent("route-points", spec.routePointCount.formatted()),
                CacheKeyComponent("source-points", spec.sourcePointCount.formatted()),
                CacheKeyComponent("distance-km", String(format: "%.1f", spec.distanceKilometers)),
            ]
        case .chart(let spec):
            return [
                CacheKeyComponent("chart-samples", spec.sampleCount.formatted()),
                CacheKeyComponent("budget-ms", Int(spec.budgetMilliseconds).formatted()),
            ]
        case .report(let spec):
            return [
                CacheKeyComponent("metrics", spec.metricTitles.count.formatted()),
                CacheKeyComponent("checklist", spec.checklist.count.formatted()),
                CacheKeyComponent("tiles", spec.tileCount.formatted()),
            ]
        }
    }
}

struct MapSnapshotSpec: Hashable, Sendable {
    let center: MapCoordinate
    let latitudeMeters: Double
    let longitudeMeters: Double
    let routeResourceName: String
    let routePointCount: Int
    let sourcePointCount: Int
    let distanceKilometers: Double
    let routeDescription: String
    let accentColor: ArtifactColor
}

struct ChartSnapshotSpec: Hashable, Sendable {
    let title: String
    let subtitle: String
    let sampleCount: Int
    let budgetMilliseconds: Double
    let accentColor: ArtifactColor
    let storageColor: ArtifactColor
    let memoryColor: ArtifactColor
}

struct ChartSample: Identifiable, Hashable, Sendable {
    let label: String
    let generatedMilliseconds: Double
    let storageMilliseconds: Double
    let memoryMilliseconds: Double
    let hitRate: Double

    var id: String {
        label
    }
}

struct ReportSnapshotSpec: Hashable, Sendable {
    let title: String
    let subtitle: String
    let routeCaption: String
    let metricTitles: [String]
    let checklist: [String]
    let tileCount: Int
    let accentColor: ArtifactColor
    let stampColor: ArtifactColor
}

struct ReportMetric: Hashable, Sendable {
    let title: String
    let value: String
    let caption: String
}

struct MapCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    var cacheComponent: String {
        "\(latitude.roundedForCache),\(longitude.roundedForCache)"
    }

    var displayString: String {
        "\(latitude.roundedForDisplay), \(longitude.roundedForDisplay)"
    }
}

struct ArtifactColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

private extension Double {
    var roundedForCache: String {
        String(format: "%.5f", self)
    }

    var roundedForDisplay: String {
        String(format: "%.4f", self)
    }
}
