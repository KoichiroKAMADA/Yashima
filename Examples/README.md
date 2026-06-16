# Examples

## YashimaPreviewLab

`YashimaPreviewLab` is a small iOS sample app that demonstrates Yashima as a
cache for expensive app-generated preview artifacts.

Open:

```sh
Examples/YashimaPreviewLab/YashimaPreviewLab.xcodeproj
```

The sample generates MapKit snapshots, Swift Charts snapshots, and SwiftUI
ticket-style manifests, stores them with Yashima, and benchmarks generation,
memory hits, and storage hits.
