import SwiftUI
import Yashima

struct PreviewBenchmarkScreen: View {
    @StateObject private var viewModel = CacheDemoViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recipeSelector
                previewPanel
                controls
                benchmarkTable
                details
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Yashima Preview Lab")
    }
}

private extension PreviewBenchmarkScreen {
    var recipeSelector: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.recipes) { recipe in
                Button {
                    viewModel.select(recipe)
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: recipe.systemImageName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(recipe.shortTitle)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(recipe == viewModel.selectedRecipe ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        recipe == viewModel.selectedRecipe
                            ? Color.accentColor
                            : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recipe.title)
            }
        }
    }

    var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: viewModel.selectedRecipe.systemImageName)
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Generate an artifact preview")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .padding(18)
                        .background(.regularMaterial, in: Circle())
                }
            }

            HStack(spacing: 12) {
                Label(viewModel.source?.label ?? "Not loaded", systemImage: viewModel.source.systemImageName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.source.tint)

                Spacer()

                Label(viewModel.elapsedText, systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.selectedRecipe.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    var controls: some View {
        Button {
            Task {
                await viewModel.runBenchmark()
            }
        } label: {
            Label("Run Benchmark", systemImage: "stopwatch")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(viewModel.isWorking)
    }

    var benchmarkTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cache benchmark")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Operation")
                    Text("Source")
                    Text("Time")
                    Text("Bytes")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Divider()
                    .gridCellColumns(4)

                ForEach(viewModel.benchmarkRows) { row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.step.title)
                                .font(.subheadline.weight(.semibold))
                            Text(row.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 5) {
                            if row.state == .running {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: row.source.systemImageName)
                                    .foregroundStyle(row.source.tint)
                            }

                            Text(row.sourceText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(row.source.tint)
                        }

                        Text(row.elapsedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.state == .failed ? .red : .primary)

                        Text(row.byteCountText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if row.id != viewModel.benchmarkRows.last?.id {
                        Divider()
                            .gridCellColumns(4)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cache details")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(viewModel.detailRows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.footnote)
                    .padding(.vertical, 9)

                    if row.id != viewModel.detailRows.last?.id {
                        Divider()
                    }
                }

                if viewModel.detailRows.isEmpty {
                    Text("Run the generator to inspect the cache entry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private extension CacheDemoViewModel.BenchmarkRow {
    var sourceText: String {
        switch state {
        case .waiting:
            return "Not run"
        case .running:
            return "Running"
        case .completed:
            return source?.label ?? "-"
        case .failed:
            return "Failed"
        }
    }
}

extension Optional where Wrapped == YCache.Source {
    var systemImageName: String {
        switch self {
        case .generated:
            return "wand.and.sparkles"
        case .memory:
            return "memorychip"
        case .storage:
            return "internaldrive"
        case nil:
            return "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .generated:
            return .orange
        case .memory:
            return .blue
        case .storage:
            return .green
        case nil:
            return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        PreviewBenchmarkScreen()
    }
}
