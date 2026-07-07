import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                PreviewBenchmarkScreen()
            }
            .tabItem {
                Label("Benchmark", systemImage: "stopwatch")
            }

            NavigationStack {
                ScrollingThumbnailsScreen()
            }
            .tabItem {
                Label("Thumbnails", systemImage: "square.grid.3x3")
            }

            NavigationStack {
                TextArtifactsScreen()
            }
            .tabItem {
                Label("Text", systemImage: "doc.text")
            }
        }
    }
}

#Preview {
    ContentView()
}
