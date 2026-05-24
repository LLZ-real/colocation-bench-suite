# Offline Workload Fingerprint

## Purpose

This document summarizes the resource fingerprint of each offline workload and connects it to the observed TaoBench slowdown.

Stage 1 fixes TaoBench as the online workload and varies the offline workload type and intensity.

## Stable baseline

TaoBench-only baseline:

- QPS: 165508.28
- P99 latency: 99.327 ms

## Synthetic offline workloads

| workload | intensity | expected pressure | QPS degradation | P99 slowdown | observation |
|---|---:|---|---:|---:|---|
| iBench CPU | w8 | CPU execution | -0.4% | 0.99x | little impact |
| iBench CPU | w30 | CPU execution | 0.5% | 1.00x | little impact |
| iBench memBw | w2 | memory bandwidth | 8.9% | 1.08x | mild impact |
| iBench memBw | w4 | memory bandwidth | 34.7% | 1.49x | clear impact |
| iBench memBw | w8 | memory bandwidth | 58.6% | 2.34x | strong impact |
| iBench L3 | w2 | LLC/cache | 13.8% | 1.14x | mild impact |
| iBench L3 | w4 | LLC/cache | 44.1% | 1.74x | clear impact |
| iBench L3 | w8 | LLC/cache | 55.4% | 2.20x | strong impact |

## Real offline workloads

| workload | intensity | expected pressure | QPS degradation | P99 slowdown | observation |
|---|---:|---|---:|---:|---|
| SPEC 505.mcf_r | train c1 | weak / smoke | 1.5% | 1.01x | too weak |
| SPEC 505.mcf_r | ref c2 | irregular memory/cache | 6.2% | 1.06x | mild impact |
| SPEC 505.mcf_r | ref c4 | irregular memory/cache | 11.2% | 1.11x | mild to moderate impact |
| SPEC 505.mcf_r | ref c8 | irregular memory/cache | 29.3% | 1.51x | moderate impact |
| SPEC 519.lbm_r | ref c2 | streaming memory bandwidth | 13.8% | 1.14x | mild impact |
| SPEC 519.lbm_r | ref c4 | streaming memory bandwidth | 42.2% | 1.68x | clear impact |
| SPEC 519.lbm_r | ref c8 | streaming memory bandwidth | 65.1% | 2.78x | severe impact |

## Main observations

1. CPU-only pressure has little effect under the current placement.

   TaoBench server and offline workloads are colocated on the same socket but on different physical cores. Therefore, they do not share SMT sibling threads or the same execution units.

2. Memory bandwidth pressure strongly affects TaoBench.

   iBench memBw w8 causes 58.6% QPS degradation and 2.34x P99 slowdown. SPEC 519.lbm_r ref c8 causes 65.1% QPS degradation and 2.78x P99 slowdown.

3. LLC/cache pressure also strongly affects TaoBench.

   iBench L3 w8 causes 55.4% QPS degradation and 2.20x P99 slowdown.

4. Real offline workloads show workload-dependent interference.

   SPEC 505.mcf_r causes moderate slowdown, while SPEC 519.lbm_r causes severe slowdown. This suggests that different offline resource fingerprints lead to different online slowdowns.

5. Interference intensity matters.

   For both mcf and lbm, increasing SPEC copies from c2 to c4 to c8 increases TaoBench slowdown.

## PMU extension

Representative PMU points:

| point | purpose |
|---|---|
| baseline | no-interference reference |
| iBench memBw w8 | synthetic memory bandwidth pressure |
| iBench L3 w8 | synthetic cache pressure |
| SPEC mcf ref c8 | real moderate interference |
| SPEC lbm ref c8 | real severe interference |

Expected PMU metrics:

- IPC
- cache miss rate
- LLC load miss rate
- branch miss rate
- context switches
- CPU migrations

PMU results should be added to `docs/pmu_representative_points.csv`.

