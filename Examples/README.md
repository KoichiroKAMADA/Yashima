# Examples

## YashimaPreviewLab

`YashimaPreviewLab` is a small iOS sample app that demonstrates Yashima as a
cache for expensive app-generated preview artifacts.

Open:

```sh
Examples/YashimaPreviewLab/YashimaPreviewLab.xcodeproj
```

The sample includes:

- A benchmark for MapKit snapshots, Swift Charts snapshots, and SwiftUI
  ticket-style manifests.
- A scrolling thumbnail grid that uses `.task(id:)` with
  `YCache.Options.uiLifecycle`.
- A text-artifact screen that stores generated `Codable` metadata and
  compressed text-like payloads.
