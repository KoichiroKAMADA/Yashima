# YashimaPreviewLab

YashimaPreviewLab is a small iOS sample app for Yashima.

It contains three tabs:

- `Benchmark` generates three kinds of preview artifacts, then caches the
  generated JPEGs with Yashima:
  - A MapKit route snapshot based on a sanitized 9,426-point coordinate route
    around Goshikidai and Yashima.
  - A Swift Charts performance snapshot.
  - A SwiftUI ticket-style manifest rendered with `ImageRenderer`.
- `Thumbnails` shows a scrolling `LazyVGrid` where each synthetic cell uses
  `.task(id:)` and `YCache.Options.uiLifecycle`.
- `Text` stores a small `Codable` metadata artifact and a larger text-like
  payload through `CompressedDataCodec`.

These examples match the intended Yashima use case: app-generated artifacts that
are expensive but safe to regenerate.

The route snapshot uses a trimmed coordinate list for display. Source metadata,
timestamps, and the original start/end area are not included in the sample app.

## Try It

1. Open `YashimaPreviewLab.xcodeproj` in Xcode.
2. Select the `YashimaPreviewLab` scheme.
3. Run on an iOS Simulator.

For a physical device, change the signing team and bundle identifier to values
from your own Apple Developer account.

## What To Watch

- `Benchmark` switches between MapKit, Swift Charts, and SwiftUI
  rendering examples.
- `Run Benchmark` first forces artifact generation.
- The memory row reads the same entry from the same `YCache` instance.
- The disk row creates a new `YCache` instance using the same storage
  directory, so it demonstrates storage-backed recovery.
- `Thumbnails` resolves every visible grid tile with `.uiLifecycle`, then shows
  whether each tile came from generation, memory, or storage.
- `Text` demonstrates that Yashima can cache structured `Codable` values and
  larger generated text payloads, not only images.

The benchmark table shows generation, memory, and storage timings side by side.
Memory and storage rows use the fastest result from five reads to reduce
one-off scheduling noise in the sample UI.

The app uses `resolve(for:codec:)` instead of the shorter `jpeg(for:)` helper so
it can display whether the result came from `.generated`, `.memory`, or
`.storage`.
