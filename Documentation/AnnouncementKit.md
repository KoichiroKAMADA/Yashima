<p align="right">
  <strong>English</strong> | <a href="AnnouncementKit.ja.md">日本語</a>
</p>

# Announcement Kit

This page collects public-safe wording for maintainers when introducing Yashima
after a release, Swift Package Index refresh, or documentation update.

Before major outreach, confirm that:

- the latest GitHub Release is public;
- Swift Package Index shows the latest release and real compatibility results;
- README badges do not show `pending`;
- benchmark numbers were generated from the current `Benchmarks` command on the
  environment being quoted.

## One-Paragraph Pitch

Yashima is a Swift Concurrency-first local artifact cache for generated app
artifacts. It is built for values an app can recreate but should not recreate on
every scroll, navigation, launch, or return visit: thumbnails, previews, map
snapshots, chart snapshots, rendered document payloads, summaries, waveforms,
and small derived metadata. The public API keeps the common path to one
async get-or-generate call while still preserving codec identity, memory and
storage tiers, single-flight generation, cache trimming, and UI lifecycle
cancellation.

## Short Pitch

Yashima caches generated local artifacts in Swift apps: not remote images, not
database records, but expensive results your app can safely recreate. It gives
those workflows a small async API, typed codecs, memory + disk reuse,
single-flight generation, and SwiftUI-friendly cancellation.

## Public Claim Boundaries

Safe to say:

- Yashima 1.0.0 is the first stable API release for the current generated
  artifact cache surface.
- Yashima is intended for disposable local artifacts, not original user data.
- Yashima is not a URL image downloader and not a database.
- The repository includes DocC source, examples, recipes, a comparison guide,
  adoption measurement guidance, FAQ, and a local benchmark harness.
- The maintainer reports using Yashima across shipped App Store apps. Treat
  app-level usage and download numbers as maintainer-reported unless a public
  source is cited next to the claim.

Do not say:

- Yashima makes disk I/O non-blocking.
- Benchmark numbers alone explain Yashima's value.
- Yashima is a drop-in replacement for Nuke, Kingfisher, SwiftData, Core Data,
  SQLite, or GRDB.
- Benchmark numbers prove general performance without the command, environment,
  payload size, generator scenario, and cache-hit boundary.

## Quantitative Summary Template

Use this only after filling in current, verified values:

```text
Yashima 1.0.0 is a stable Swift package for caching generated local artifacts.
It is maintainer-reported as already used across [N] shipped App Store apps,
including workloads such as [workload examples]. In [measured app workload],
app-side counters showed [before generator runs] before Yashima and [after
generator runs / memory hits / storage hits] after adoption. These numbers
describe avoided local regeneration in that workload, not a universal
performance claim.
```

## Comment Reply Seeds

### How is this different from Kingfisher or Nuke?

Kingfisher and Nuke are excellent image pipelines for remote image loading,
decoding, and caching. Yashima focuses on local generated artifacts: values your
app produces itself, such as thumbnails, rendered previews, chart snapshots, or
document payloads.

### What is the speed value?

The value is avoiding repeated local generation in apps that currently recreate
the same derived artifacts over and over. Yashima gives AI agents and developers
a reliable package-shaped way to add that local cache without turning every app
into a custom cache implementation project.

### Why not use a database?

Use a database for structured data that must be preserved. Yashima is for
derived values that can be deleted and regenerated.

### Why does `uiLifecycle` exist?

Scrolling cells and grid tiles often start work that no one cares about once
the view disappears. `YCache.Options.uiLifecycle` lets all-waiters-gone
cancellation be part of that cache request instead of leaving each caller to
rebuild the same policy.

## Link Set

- GitHub: https://github.com/KoichiroKAMADA/Yashima
- Release: https://github.com/KoichiroKAMADA/Yashima/releases
- Swift Package Index: https://swiftpackageindex.com/KoichiroKAMADA/Yashima
- Discussions: https://github.com/KoichiroKAMADA/Yashima/discussions
- Recipes: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/Recipes.md
- Adoption Measurement: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/AdoptionMeasurement.md
- FAQ: https://github.com/KoichiroKAMADA/Yashima/blob/main/Documentation/FAQ.md
- Benchmarks: https://github.com/KoichiroKAMADA/Yashima/tree/main/Benchmarks
