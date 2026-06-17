# Yashima Stress Tests

This directory contains an optional stress runner for Yashima. It is separate
from the main `swift test` suite so regular package validation stays fast and
deterministic.

The runner checks correctness under concurrent get-or-generate calls, mixed
artifact types, lifecycle operations, storage trimming, exact-capacity
replacement, concurrent quota pressure, default memory-limit pressure,
oversized-entry cleanup, recoverable corruption, and cancellation churn. It is
not a benchmark harness: durations are reported as observations, but pass/fail
is based on cache correctness.

## Running

From the repository root:

```sh
swift run --package-path StressTests YashimaStressRunner --profile smoke
```

Profiles:

- `smoke`: quick local check for ordinary development.
- `standard`: broader local check for larger behavior changes.
- `soak`: longer local run before high-risk changes or releases.

Useful options:

```sh
swift run --package-path StressTests YashimaStressRunner --profile standard --seed 42
swift run --package-path StressTests YashimaStressRunner --profile smoke --format json
swift run --package-path StressTests YashimaStressRunner --profile smoke --root /tmp/yashima-stress --keep-artifacts
```

`--root` is a parent directory for generated workspaces. Generated cache files
are disposable and must not be committed.

## Profiles

| Profile | Keys | Concurrency | Single-flight fanout | Payload range | Timeout |
| --- | ---: | ---: | ---: | ---: | ---: |
| `smoke` | 120 | 24 | 64 | 1-32 KiB | 60s |
| `standard` | 1,000 | 64 | 256 | 1-128 KiB | 5m |
| `soak` | 5,000 | 128 | 512 | 1-256 KiB | 30m |

## Scenario Coverage

| Scenario | What it checks |
| --- | --- |
| `SingleFlightBurst` | Many concurrent requests for the same missing key share one generation and persist the generated value. |
| `ConcurrentArtifactMix` | `Data`, `Codable`, PNG, and JPEG artifacts can be generated concurrently and read back from storage. |
| `LifecycleUnderLoad` | Refresh, lookup, metadata, store, remove, and namespace removal remain coherent under mixed operations. |
| `StorageLimitTrim` | Storage stays within `storageMaximumByteCount` while older entries are trimmed and misses can regenerate. |
| `ExactCapacityReplacement` | A cache that can hold exactly one payload replaces the old entry and keeps the newest one readable from storage. |
| `ConcurrentQuotaPressure` | Many concurrent writes under a tight quota leave valid retained entries, trim older entries, and keep temporary files clean. |
| `MemoryLimitPressure` | Default memory limits evict older entries while persisted storage remains readable. |
| `OversizedEntryPressure` | Entries larger than the quota are not retained, and later valid entries can still be persisted. |
| `CorruptionRecovery` | Recoverable data and metadata corruption can be treated as misses, while strict read policy still throws. |
| `CancellationChurn` | Cancellation around shared generation does not leave the cache unable to serve later requests. |

## Public Data Policy

All stress payloads are synthetic and deterministic. Do not add real app data,
private logs, real screenshots, location data, credentials, or machine-specific
configuration to these tests.
