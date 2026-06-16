import Charts
import CoreGraphics
import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit
import Yashima

enum ArtifactGenerator {
    @MainActor
    static func render(_ recipe: ArtifactRecipe) async throws -> ImageCodec.Value {
        try Task.checkCancellation()

        // Treat this method as the expensive producer. Yashima calls it only
        // when the requested key/codec pair is missing or explicitly refreshed.
        switch recipe.spec {
        case .map(let spec):
            return try await makeMapSnapshotValue(for: recipe, spec: spec)
        case .chart(let spec):
            return try renderSwiftUIView(
                ChartSnapshotView(
                    spec: spec,
                    samples: ChartSample.randomSamples(count: spec.sampleCount)
                )
            )
        case .report(let spec):
            return try renderSwiftUIView(
                TicketSnapshotView(
                    spec: spec,
                    ticket: TicketSnapshotData.random(spec: spec)
                )
            )
        }
    }
}

enum ArtifactGeneratorError: Error {
    case snapshotMissing
    case imageRenderingFailed
    case routeResourceMissing(String)
    case malformedRouteCoordinate(line: Int)
}

private extension ArtifactGenerator {
    static let outputSize = CGSize(width: 960, height: 540)

    @MainActor
    static func makeMapSnapshotValue(
        for recipe: ArtifactRecipe,
        spec: MapSnapshotSpec
    ) async throws -> ImageCodec.Value {
        // The full 9,653-point route is loaded during generation on purpose.
        // Cache hits skip this load, the MapKit snapshot, and the overlay draw.
        let route = try loadRoute(named: spec.routeResourceName)
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: spec.center.locationCoordinate,
            latitudinalMeters: spec.latitudeMeters,
            longitudinalMeters: spec.longitudeMeters
        )
        options.size = outputSize
        options.scale = 2
        options.mapType = .standard
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)

        return try await withCheckedThrowingContinuation { continuation in
            snapshotter.start { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let snapshot else {
                    continuation.resume(throwing: ArtifactGeneratorError.snapshotMissing)
                    return
                }

                let image = drawOverlay(on: snapshot, recipe: recipe, spec: spec, route: route)
                continuation.resume(returning: ImageCodec.Value(image))
            }
        }
    }

    @MainActor
    static func renderSwiftUIView<Content: View>(_ content: Content) throws -> ImageCodec.Value {
        // SwiftUI views can also be generated artifacts. ImageRenderer turns
        // them into platform images that the ImageCodec can encode as JPEG.
        let renderer = ImageRenderer(
            content: content
                .frame(width: outputSize.width, height: outputSize.height)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        renderer.isOpaque = true

        guard let image = renderer.uiImage else {
            throw ArtifactGeneratorError.imageRenderingFailed
        }

        return ImageCodec.Value(image)
    }

    static func drawOverlay(
        on snapshot: MKMapSnapshotter.Snapshot,
        recipe: ArtifactRecipe,
        spec: MapSnapshotSpec,
        route: [MapCoordinate]
    ) -> UIImage {
        let image = snapshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { rendererContext in
            image.draw(at: .zero)

            let context = rendererContext.cgContext
            drawRoute(route, snapshot: snapshot, in: context, color: spec.accentColor)
            drawEndpointMarkers(route, snapshot: snapshot, in: context, color: spec.accentColor)
            drawBadge(recipe: recipe, imageSize: image.size)
        }
    }

    static func loadRoute(named resourceName: String) throws -> [MapCoordinate] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "csv") else {
            throw ArtifactGeneratorError.routeResourceMissing(resourceName)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        var route: [MapCoordinate] = []
        route.reserveCapacity(9_653)

        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 2,
                  let latitude = Double(fields[0]),
                  let longitude = Double(fields[1]) else {
                throw ArtifactGeneratorError.malformedRouteCoordinate(line: offset + 1)
            }

            route.append(MapCoordinate(latitude: latitude, longitude: longitude))
        }

        return route
    }

    static func drawRoute(
        _ route: [MapCoordinate],
        snapshot: MKMapSnapshotter.Snapshot,
        in context: CGContext,
        color: ArtifactColor
    ) {
        let points = route
            .map { snapshot.point(for: $0.locationCoordinate) }
            .filter { imageRect(for: snapshot.image).insetBy(dx: -24, dy: -24).contains($0) }

        guard points.count >= 2 else {
            return
        }

        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        context.saveGState()
        color.uiColor(alpha: 0.30).setStroke()
        path.lineWidth = 18
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        color.uiColor(alpha: 0.96).setStroke()
        path.lineWidth = 7
        path.stroke()
        context.restoreGState()
    }

    static func drawEndpointMarkers(
        _ route: [MapCoordinate],
        snapshot: MKMapSnapshotter.Snapshot,
        in context: CGContext,
        color: ArtifactColor
    ) {
        let coordinates = Array(Set([route.first, route.last].compactMap { $0 }))

        for coordinate in coordinates {
            let point = snapshot.point(for: coordinate.locationCoordinate)
            guard imageRect(for: snapshot.image).insetBy(dx: -24, dy: -24).contains(point) else {
                continue
            }

            context.saveGState()
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30)).fill()

            color.uiColor(alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)).fill()
            context.restoreGState()
        }
    }

    static func drawBadge(recipe: ArtifactRecipe, imageSize: CGSize) {
        let badgeRect = CGRect(x: 28, y: imageSize.height - 96, width: 378, height: 60)
        let path = UIBezierPath(roundedRect: badgeRect, cornerRadius: 18)

        UIColor.black.withAlphaComponent(0.52).setFill()
        path.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.76),
        ]

        recipe.title.draw(
            in: CGRect(x: badgeRect.minX + 18, y: badgeRect.minY + 8, width: badgeRect.width - 36, height: 26),
            withAttributes: titleAttributes
        )
        "MapKit snapshot + Yashima".draw(
            in: CGRect(x: badgeRect.minX + 18, y: badgeRect.minY + 35, width: badgeRect.width - 36, height: 18),
            withAttributes: subtitleAttributes
        )
    }

    static func imageRect(for image: UIImage) -> CGRect {
        CGRect(origin: .zero, size: image.size)
    }
}

private struct ChartSnapshotView: View {
    let spec: ChartSnapshotSpec
    let samples: [ChartSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(spec.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(spec.subtitle)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("CACHE IMPACT")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(Int(averageHitRate * 100))%")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(spec.memoryColor.color)
                }
            }

            HStack(alignment: .center, spacing: 18) {
                Chart {
                    ForEach(samples) { sample in
                        AreaMark(
                            x: .value("Time", sample.label),
                            y: .value("Generate", sample.generatedMilliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    spec.accentColor.color.opacity(0.30),
                                    spec.accentColor.color.opacity(0.03),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", sample.label),
                            y: .value("Generate", sample.generatedMilliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(spec.accentColor.color)

                        PointMark(
                            x: .value("Time", sample.label),
                            y: .value("Generate", sample.generatedMilliseconds)
                        )
                        .symbolSize(sample.generatedMilliseconds == peakGeneratedMilliseconds ? 105 : 42)
                        .foregroundStyle(spec.accentColor.color)

                        LineMark(
                            x: .value("Time", sample.label),
                            y: .value("Storage", sample.storageMilliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(spec.storageColor.color)

                        LineMark(
                            x: .value("Time", sample.label),
                            y: .value("Memory", sample.memoryMilliseconds)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 7]))
                        .foregroundStyle(spec.memoryColor.color)
                    }

                    RuleMark(y: .value("Interaction budget", spec.budgetMilliseconds))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("120 ms budget")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: 0...chartUpperBound)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let milliseconds = value.as(Double.self) {
                                Text("\(Int(milliseconds))")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(height: 300)

                VStack(alignment: .leading, spacing: 12) {
                    ChartLegendDot(title: "Generate", value: "\(Int(peakGeneratedMilliseconds)) ms", color: spec.accentColor.color)
                    ChartLegendDot(title: "Storage", value: "\(Int(averageStorageMilliseconds)) ms avg", color: spec.storageColor.color)
                    ChartLegendDot(title: "Memory", value: String(format: "%.1f ms avg", averageMemoryMilliseconds), color: spec.memoryColor.color)

                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Generated charts are intentionally expensive.")
                            .font(.system(size: 15, weight: .bold))
                        Text("The same JPEG artifact can come back from memory or disk without re-rendering the chart.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 224, alignment: .leading)
            }

            HStack(spacing: 12) {
                MetricPill(title: "Samples", value: samples.count.formatted(), color: spec.accentColor.color)
                MetricPill(title: "Peak render", value: "\(Int(peakGeneratedMilliseconds)) ms", color: spec.accentColor.color)
                MetricPill(title: "Best memory", value: String(format: "%.1f ms", bestMemoryMilliseconds), color: spec.memoryColor.color)
            }
        }
        .padding(32)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var peakGeneratedMilliseconds: Double {
        samples.map(\.generatedMilliseconds).max() ?? 0
    }

    private var averageStorageMilliseconds: Double {
        average(samples.map(\.storageMilliseconds))
    }

    private var averageMemoryMilliseconds: Double {
        average(samples.map(\.memoryMilliseconds))
    }

    private var bestMemoryMilliseconds: Double {
        samples.map(\.memoryMilliseconds).min() ?? 0
    }

    private var averageHitRate: Double {
        average(samples.map(\.hitRate))
    }

    private var chartUpperBound: Double {
        max(900, (peakGeneratedMilliseconds / 100).rounded(.up) * 100 + 100)
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) / Double(values.count)
    }
}

private extension ChartSample {
    static func randomSamples(count: Int) -> [ChartSample] {
        let labels = ["08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00", "17:00"]
        let clampedCount = max(3, min(count, labels.count))

        return (0..<clampedCount).map { index in
            let generated = Double.random(in: 520...980)
            let storage = Double.random(in: 18...48)
            let memory = Double.random(in: 1.2...4.8)
            let hitRateBase = Double(index + 2) / Double(clampedCount + 2)
            let hitRate = min(0.96, max(0.28, hitRateBase + Double.random(in: -0.08...0.10)))

            return ChartSample(
                label: labels[index],
                generatedMilliseconds: generated,
                storageMilliseconds: storage,
                memoryMilliseconds: memory,
                hitRate: hitRate
            )
        }
    }
}

private struct TicketSnapshotView: View {
    let spec: ReportSnapshotSpec
    let ticket: TicketSnapshotData

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.93, blue: 0.88)

            RoundedRectangle(cornerRadius: 34)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 16)
                .padding(28)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YASHIMA CACHE PASS")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(spec.accentColor.color)
                        Text(spec.title)
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                        Text(spec.subtitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ticket.primaryValue)
                            .font(.system(size: 76, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(ticket.primaryCaption.uppercased())
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        ForEach(ticket.metrics, id: \.title) { metric in
                            TicketMetricView(metric: metric, color: spec.accentColor.color)
                        }
                    }

                    Spacer(minLength: 0)

                    Text("Generated as a SwiftUI view, encoded as a JPEG artifact, then resolved through the same cache path.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 62)
                .padding(.vertical, 54)
                .frame(width: 594, alignment: .leading)

                TicketPerforation()
                    .stroke(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 2, dash: [7, 9], dashPhase: 2))
                    .frame(width: 1)
                    .padding(.vertical, 52)

                VStack(alignment: .center, spacing: 24) {
                    ZStack {
                        Circle()
                            .stroke(spec.stampColor.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 8]))
                        VStack(spacing: 2) {
                            Text(ticket.stampWord)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                            Text("CACHE")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(spec.stampColor.color)
                    }
                    .frame(width: 124, height: 124)

                    TicketCodeGrid(codes: ticket.tileCodes, color: spec.accentColor.color)

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(spec.checklist.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 9) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(spec.accentColor.color)
                                Text(item)
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 52)
                .frame(width: 310)
            }
            .padding(28)
        }
    }
}

private struct TicketSnapshotData: Sendable {
    let primaryValue: String
    let primaryCaption: String
    let metrics: [ReportMetric]
    let tileCodes: [String]
    let stampWord: String

    static func random(spec: ReportSnapshotSpec) -> TicketSnapshotData {
        let distance = Double.random(in: 86.0...132.0)
        let pointCount = Int.random(in: 7_400...12_800)
        let seed = Int.random(in: 100_000...999_999)
        let batch = "\(randomLetter())\(Int.random(in: 10...99))"
        let stampWords = ["READY", "FRESH", "LIVE", "NEW"]

        return TicketSnapshotData(
            primaryValue: String(format: "%.1f km", distance),
            primaryCaption: spec.routeCaption,
            metrics: [
                ReportMetric(title: spec.metricTitles[safe: 0] ?? "Points", value: pointCount.formatted(), caption: "generated"),
                ReportMetric(title: spec.metricTitles[safe: 1] ?? "Seed", value: seed.formatted(), caption: "run id"),
                ReportMetric(title: spec.metricTitles[safe: 2] ?? "Batch", value: batch, caption: "ticket"),
            ],
            tileCodes: randomTileCodes(count: spec.tileCount),
            stampWord: stampWords.randomElement() ?? "READY"
        )
    }

    private static func randomTileCodes(count: Int) -> [String] {
        (0..<count).map { _ in
            "\(randomLetter())\(randomLetter())"
        }
    }

    private static func randomLetter() -> String {
        String("ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement() ?? "Y")
    }
}

private struct TicketMetricView: View {
    let metric: ReportMetric
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(metric.value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(metric.caption)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TicketCodeGrid: View {
    let codes: [String]
    let color: Color

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        Text(codes.indices.contains(index) ? codes[index] : "--")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .frame(width: 58, height: 42)
                            .foregroundStyle(index.isMultiple(of: 2) ? Color.white : color)
                            .background(
                                index.isMultiple(of: 2) ? color : color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                }
            }
        }
    }
}

private struct TicketPerforation: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct ChartLegendDot: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(width: 10, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension MapCoordinate {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension ArtifactColor {
    var color: Color {
        Color(uiColor: uiColor(alpha: 1))
    }

    func uiColor(alpha: Double) -> UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
