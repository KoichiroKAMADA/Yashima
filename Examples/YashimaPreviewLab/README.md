# YashimaPreviewLab

YashimaPreviewLab is a minimal iOS sample app for Yashima.

It generates three kinds of preview artifacts, then caches the generated JPEGs
with Yashima:

- A MapKit route snapshot based on a full 9,653-point GPX-style cycling route
  from Goshikidai to Yashima.
- A Swift Charts performance snapshot.
- A SwiftUI ticket-style manifest rendered with `ImageRenderer`.

This matches the intended Yashima use case: app-generated artifacts that are
expensive but safe to regenerate.

The route snapshot uses the full coordinate list for display. The source GPX
metadata and timestamps are not included in the sample app.

## Try It

1. Open `YashimaPreviewLab.xcodeproj` in Xcode.
2. Select the `YashimaPreviewLab` scheme.
3. Run on an iOS Simulator.

For a physical device, change the signing team and bundle identifier to values
from your own Apple Developer account.

## What To Watch

- `Artifact recipes` switches between MapKit, Swift Charts, and SwiftUI
  rendering examples.
- `Run Benchmark` first forces artifact generation.
- The memory row reads the same entry from the same `YCache` instance.
- The disk row creates a new `YCache` instance using the same storage
  directory, so it demonstrates storage-backed recovery.

The benchmark table shows generation, memory, and storage timings side by side.
Memory and storage rows use the fastest result from five reads to reduce
one-off scheduling noise in the sample UI.

The app uses `resolve(for:codec:)` instead of the shorter `jpeg(for:)` helper so
it can display whether the result came from `.generated`, `.memory`, or
`.storage`.
