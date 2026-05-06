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

CPU-only interference on separate physical cores has little effect when SMT is not shared. This is consistent with the expectation that isolated CPU-only workloads do not strongly compete for the online server's private execution resources, L1 cache, or L2 cache.

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

Under physical-core isolation without SMT sharing, memory-bandwidth interference has a strong impact on TaoBench, while CPU-only interference has little impact.

This supports the working hypothesis that, without hyperthreading/core sharing, the main colocation interference path is not private CPU execution resources, but shared socket-level resources such as LLC, memory bandwidth, and the memory controller.

## Next steps

1. Repeat the TaoBench-only baseline to confirm stability.
2. Repeat iBench memBw with 8 workers to confirm reproducibility.
3. Run a memBw intensity sweep, for example workers = 2, 4, 8.
4. Add iBench l3 interference to evaluate LLC sensitivity.
5. Keep PMU/perf profiling separate from primary performance experiments.
