# Benchmarks

This directory contains a small local benchmark harness for Yashima. It is
separate from `StressTests`, which validate correctness under heavier synthetic
workloads.

Run:

```sh
swift run --package-path Benchmarks YashimaBenchmarks --iterations 200
```

Optional parameters:

```sh
swift run --package-path Benchmarks YashimaBenchmarks \
  --iterations 500 \
  --payload-bytes 65536
```

The harness measures:

- memory hits from an already warm `YCache`;
- storage hits through a fresh `YCache` using the same storage directory;
- generated writes for unique keys;
- a 100-waiter single-flight miss for one generated artifact.

Benchmark output is local evidence only. Do not quote numbers publicly without
the command, payload size, operating system, Swift toolchain, and enough context
for another developer to reproduce the run.
