# Benchmarks

This directory contains a small local benchmark harness for Yashima. It is
separate from `StressTests`, which validate correctness under heavier synthetic
workloads.

Run:

```sh
swift run -c release --package-path Benchmarks YashimaBenchmarks --iterations 200
```

Optional parameters:

```sh
swift run -c release --package-path Benchmarks YashimaBenchmarks \
  --iterations 500 \
  --payload-bytes 65536 \
  --generator-work-factor 8
```

The harness measures:

- repeated synthetic local generation without caching;
- memory hits from an already warm `YCache`;
- storage hits through a fresh `YCache` using the same storage directory;
- generated writes for unique keys;
- a 100-waiter single-flight miss for one generated artifact.

The uncached row is a reference for the cost of repeatedly regenerating a local
artifact. It is not a comparison with another cache engine or cache strategy.

## Maintainer Sample Run

This sample is a reproducibility fixture, not a general performance claim.
Quote benchmark numbers only with the command, payload size, environment, and
generation scenario.

Command:

```sh
swift run -c release --package-path Benchmarks YashimaBenchmarks --iterations 200
```

Environment:

- OS: macOS 26.5.1 (Build 25F80)
- Architecture: arm64
- Processor: Apple M5
- Memory: 32 GiB
- Swift: Apple Swift 6.3.2
- Payload: 65,536 bytes
- Generator work factor: 8
- Date: 2026-07-07

Result:

| Scenario | Mean ms | Min ms | Max ms |
|---|---:|---:|---:|
| uncached-regeneration | 0.436 | 0.412 | 0.589 |
| yashima-memory-hit | 0.011 | 0.008 | 0.081 |
| yashima-storage-hit | 0.622 | 0.452 | 4.254 |
| yashima-generated-write | 22.441 | 1.615 | 67.695 |
| yashima-single-flight-100 | 62.166 | 40.257 | 122.927 |

Benchmark output is local evidence only. Do not quote numbers publicly without
the command, payload size, generator work factor, operating system, Swift
toolchain, and enough context for another developer to reproduce the run.
