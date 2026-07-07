<p align="right">
  <strong>English</strong> | <a href="AdoptionMeasurement.ja.md">日本語</a>
</p>

# Adoption Measurement

Yashima's performance value is avoiding repeated local generation in apps that
currently recreate the same derived artifacts during scrolling, navigation,
launch, or return visits.

This guide helps developers and coding agents measure that value before and
after adopting Yashima.

## What To Measure

Measure the work the app used to repeat:

- how many times the producer runs for the same logical artifact;
- how often concurrent callers request the same key at the same time;
- how long the first generation takes;
- how quickly memory and storage hits return after navigation or relaunch;
- whether cache keys change when the underlying content, size, scale,
  appearance, locale, or renderer version changes;
- how much disk space the cache uses after a realistic session.

The most useful result is often a count, not a timing number.
For example, if a scrolling grid previously rendered the same thumbnail 40
times and now renders it once, the app has removed repeated work even if no
general benchmark claim is made.

## Temporary App-Side Instrumentation

For a short measurement branch, add counters around the app's generator and
Yashima call site.
Keep the counters out of release builds unless the app already has a diagnostic
system.

```swift
let resolved = try await cache.resolve(
    for: key,
    codec: ImageCodec.jpeg(quality: 0.85),
    options: .uiLifecycle
) {
    metrics.thumbnailGeneratorRuns += 1
    return try await renderThumbnail()
}

metrics.recordCacheSource(resolved.source)
```

Useful counters:

- `generatorRuns`: producer executions;
- `memoryHits`: values served from the current cache instance;
- `storageHits`: values restored from disk-backed storage;
- `generated`: values created because no cached entry existed;
- `sharedFromInFlight`: callers that received work already being generated;
- `cancelledUIWork`: UI-bound requests cancelled because no waiter remained;
- `storageBytes`: bytes reported by `storageUsage()`.

## Before And After Checks

Before adoption:

1. Pick one narrow workload, such as a thumbnail grid, document preview, map
   snapshot, or generated metadata payload.
2. Count producer executions during a realistic interaction.
3. Note whether duplicate work happens while scrolling, revisiting a screen, or
   relaunching the app.

After adoption:

1. Confirm the first request still generates the artifact correctly.
2. Confirm repeated requests for the same key do not rerun the producer.
3. Confirm relaunch or fresh cache-instance scenarios produce storage hits.
4. Confirm key changes invalidate the correct entries.
5. Confirm disk usage stays within the intended budget.

## How To Report Results

Prefer this shape:

```text
In a thumbnail grid with 120 visible and prefetched items, app-side counters
showed 120 generator runs before Yashima. After using CacheKey(asset, size,
scale, crop, rendererVersion) with JPEG storage, the same interaction produced
120 first-generation misses, then 0 generator runs on immediate revisit and
storage hits after relaunch. Disk usage for the session was 18 MB under a
128 MB budget.
```

Avoid this shape:

```text
Yashima made the app fast.
```

The first report explains the removed work.
The second report is too broad to verify.

## Future Package-Level Performance Review

Yashima package performance can be reviewed separately from adoption
measurement.
That work should start with profiling evidence and keep source-code simplicity
as a constraint.

Useful questions for a dedicated performance session:

- Are storage-hit paths spending time in metadata reads, data reads, decoding,
  actor hops, or file-system calls?
- Does generated-write cost come from encoding, metadata writing, atomic
  replacement, trim checks, or cache bookkeeping?
- Does single-flight overhead matter only in synthetic 100-waiter cases, or does
  it show up in real scrolling and launch workloads?
- Can any improvement be made without making cache identity, corruption
  handling, or storage trimming harder to reason about?

Do not trade maintainability for small timing changes without a real app
workload that justifies the cost.
