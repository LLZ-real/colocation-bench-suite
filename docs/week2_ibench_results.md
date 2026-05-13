# Week 2: TaoBench + iBench interference results

## Setup

- Online workload: TaoBench
- Online clients_per_thread: 900
- Prewarm: clients=900, 8 rounds, 60s each
- Measurement: clients=900, 300s
- Perf: disabled for primary performance results
- Server placement: socket 0 physical cores
- Offline placement: socket 0 physical cores
- Load generator placement: socket 1

## Baseline

Stable no-perf TaoBench baseline:

| workload | QPS | P99 ms |
|---|---:|---:|
| TaoBench only | ~166000 | ~98 |

## iBench CPU interference

| workload | QPS | P99 ms | observation |
|---|---:|---:|---|
| TaoBench + iBench CPU, 8 workers | 166133.17 | 98.303 | almost no degradation |

Interpretation:

Under the current placement, CPU-only interference does not cause significant degradation because the offline CPU workload runs on different physical cores and does not share SMT siblings with the online server. This is consistent with the expectation that isolated CPU-only workloads do not strongly compete for the online server's private execution resources, L1 cache, or L2 cache.

## iBench memBw interference

Run directory:

/home/lilinzhen/colocate_lab/results/cbs/20260506_211421_week2_taobench_ibench_membw_ibench_membw_8

Prewarm stability before interference:

| round | QPS | P99 ms |
|---:|---:|---:|
| 6 | 169226.74 | 107.519 |
| 7 | 168841.76 | 108.031 |
| 8 | 168464.23 | 108.031 |

Measured under iBench memBw:

| workload | QPS | P99 ms |
|---|---:|---:|
| TaoBench + iBench memBw, 8 workers | 68547.89 | 232.447 |

Approximate degradation compared with stable baseline:

| metric | value |
|---|---:|
| QPS degradation | ~58.7% |
| P99 slowdown | ~2.36x |

## Current conclusion

Under physical-core isolation without SMT sharing, memory-bandwidth interference has a strong impact on TaoBench, while CPU-only interference under the current physical-core-isolated placement does not cause significant degradation.

This supports the working hypothesis that, without hyperthreading/core sharing, the main colocation interference path is not private CPU execution resources, but shared socket-level resources such as LLC, memory bandwidth, and the memory controller.

## Next steps

1. Repeat the TaoBench-only baseline to confirm stability.
2. Repeat iBench memBw with 8 workers to confirm reproducibility.
3. Run a memBw intensity sweep, for example workers = 2, 4, 8.
4. Add iBench l3 interference to evaluate LLC sensitivity.
5. Keep PMU/perf profiling separate from primary performance experiments.

## memBw reproducibility and intensity sweep

### memBw=8 reproducibility

| run | QPS | P99 ms |
|---|---:|---:|
| memBw=8 first | 68547.89 | 232.447 |
| memBw=8 repeat | 66628.93 | 239.615 |

The memBw=8 result is reproducible. The two runs differ by only about 2.8% in QPS and about 3.1% in P99 latency.

### memBw=4 result

| workload | QPS | P99 ms |
|---|---:|---:|
| TaoBench + memBw=4 | 108052.41 | 148.479 |

### Current intensity curve

Baseline used for approximate degradation:

- QPS_baseline: 166000
- P99_baseline_ms: 98.3

| workload | QPS | QPS degradation | P99 ms | P99 slowdown |
|---|---:|---:|---:|---:|
| baseline | 166000 | 0% | 98.3 | 1.00x |
| memBw=4 | 108052.41 | ~34.9% | 148.479 | ~1.51x |
| memBw=8 first | 68547.89 | ~58.7% | 232.447 | ~2.36x |
| memBw=8 repeat | 66628.93 | ~59.9% | 239.615 | ~2.44x |

Interpretation:

The degradation increases with the number of memBw workers. This supports the conclusion that TaoBench is highly sensitive to same-socket memory bandwidth pressure under physical-core isolation.

## Final memBw intensity sweep summary

Baseline:

| workload | QPS | P99 ms |
|---|---:|---:|
| TaoBench only | 165508.28 | 99.327 |

Current Week 2 results:

| workload | workers | QPS | QPS degradation | P99 ms | P99 slowdown |
|---|---:|---:|---:|---:|---:|
| iBench CPU | 8 | 166133.17 | -0.4% | 98.303 | 0.99x |
| memBw | 2 | 150847.49 | 8.9% | 107.007 | 1.08x |
| memBw | 4 | 108052.41 | 34.7% | 148.479 | 1.49x |
| memBw | 8 | 68547.89 | 58.6% | 232.447 | 2.34x |
| memBw | 8 repeat | 66628.93 | 59.7% | 239.615 | 2.41x |

Conclusion:

The memBw intensity sweep shows a monotonic degradation trend. Under the current physical-core-isolated placement, TaoBench shows no significant degradation from CPU-only interference, but it is highly sensitive to same-socket memory bandwidth interference. This supports the hypothesis that, under physical-core isolation without SMT sharing, the dominant colocation interference path is shared socket-level memory subsystem contention rather than private core execution-resource contention under this no-SMT-sharing placement.

## L3 interference results

Current summary, using TaoBench-only baseline:

- Baseline QPS: 165508.28
- Baseline P99: 99.327 ms

| offline | workers | QPS | QPS degradation | P99 ms | P99 slowdown |
|---|---:|---:|---:|---:|---:|
| none | 0 | 165508.28 | 0.0% | 99.327 | 1.00x |
| CPU | 8 | 166133.17 | -0.4% | 98.303 | 0.99x |
| memBw | 2 | 150847.49 | 8.9% | 107.007 | 1.08x |
| memBw | 4 | 108052.41 | 34.7% | 148.479 | 1.49x |
| memBw | 8 | 68547.89 | 58.6% | 232.447 | 2.34x |
| memBw | 8 repeat | 66628.93 | 59.7% | 239.615 | 2.41x |
| L3 | 2 | 142615.00 | 13.8% | 113.151 | 1.14x |
| L3 | 4 | 92445.59 | 44.1% | 173.055 | 1.74x |
| L3 | 8 | 73893.81 | 55.4% | 218.111 | 2.20x |

## Interpretation

The CPU-only workload does not cause significant degradation under the current physical-core-isolated placement. This does not mean CPU interference is generally harmless; it means that, in this configuration, the offline CPU workload does not share SMT siblings or private core resources with the TaoBench server.

Both memBw and L3 interference cause substantial degradation, and the degradation increases with worker count. This indicates that TaoBench is sensitive to same-socket shared cache and memory-subsystem contention.

The strongest observed degradation comes from memBw=8:

- QPS drops by about 59%.
- P99 latency increases by about 2.4x.

L3=8 is also severe:

- QPS drops by about 55%.
- P99 latency increases by about 2.2x.

Overall conclusion:

Under same-socket physical-core isolation, the dominant colocation interference path for TaoBench is shared LLC / memory subsystem contention, not private CPU-core execution-resource contention.

## Note on original iBench memCap

The original iBench `memCap` workload was inspected and found to use the command-line argument as duration in seconds, not as memory size in GB.

The source code maps approximately the full system memory size and repeatedly performs `memcpy` over half of that region. Therefore, `memCap 4` does not mean 4GB memory pressure; it means running the full-memory copy loop for 4 seconds of CPU time.

As a result, the original `memCap` is not used as a controlled memory-capacity interference source in the current formal results. The previous `memCap=15` run is marked invalid because it caused abnormal TaoBench behavior and missing QPS/P99 output, likely due to excessive memory pressure or OOM-like effects.

For controlled memory-capacity experiments, a separate fixed-size memory holder/toucher should be implemented.
