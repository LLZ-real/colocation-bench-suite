# Week 3: TaoBench + SPEC CPU offline workload

## Goal

Use SPEC CPU2017 as a real offline workload and evaluate its colocation impact on TaoBench.

Compared with Week 2 synthetic iBench interference, SPEC CPU represents real application-level compute workloads.

## Online workload

- Online workload: TaoBench
- clients_per_thread: 900
- client test time: 300s
- prewarm rounds: 8
- prewarm clients_per_thread: 900
- prewarm test time: 60s
- perf: disabled for primary performance results

## Placement

- TaoBench server: socket 0 physical cores
- Offline workload: socket 0 different physical cores
- TaoBench load generator: socket 1

## Baseline

| workload | QPS | P99 ms |
|---|---:|---:|
| TaoBench only | 165508.28 | 99.327 |

## SPEC mcf train, 1 copy

| workload | SPEC size | copies | QPS | P99 ms | observation |
|---|---|---:|---:|---:|---|
| 505.mcf_r | train | 1 | 162973.17 | 100.351 | weak interference |

Interpretation:

The single-copy train-size SPEC mcf workload was successfully executed, but caused almost no degradation. This suggests that train input with one copy is too weak as an offline interference source under physical-core isolation.

## SPEC mcf train, 8 copies smoke

The smoke test confirmed that SPEC_COPIES=8 works. The offline container launched 8 copies of 505.mcf_r, and each copy consumed approximately one CPU core.

This validates the multi-copy SPEC offline workload integration.

## SPEC mcf ref, 8 copies

Status: running.

| workload | SPEC size | copies | QPS | P99 ms | observation |
|---|---|---:|---:|---:|---|
| 505.mcf_r | ref | 8 | TBD | TBD | TBD |

## Notes

- SPEC train, 1 copy is useful for validating the pipeline but is too light for meaningful interference.
- SPEC ref, 8 copies is the first formal Week 3 experiment.
- Next recommended benchmark after mcf: 519.lbm_r ref, 8 copies.

## SPEC mcf ref, 8 copies

| workload | SPEC size | copies | QPS | QPS degradation | P99 ms | P99 slowdown |
|---|---|---:|---:|---:|---:|---:|
| 505.mcf_r | ref | 8 | 116962.26 | 29.3% | 149.503 | 1.51x |

Interpretation:

Compared with the TaoBench-only baseline, 505.mcf_r with ref input and 8 copies causes clear degradation. QPS drops by about 29.3%, and P99 latency increases by about 1.51x. This confirms that SPEC CPU can serve as a real offline interference workload when using ref input and enough copies to occupy the offline cores.

The earlier train-size single-copy run was too weak, but ref-size multi-copy execution creates meaningful contention.

## SPEC lbm ref, 8 copies

| workload | SPEC size | copies | QPS | QPS degradation | P99 ms | P99 slowdown |
|---|---|---:|---:|---:|---:|---:|
| 519.lbm_r | ref | 8 | 57720.51 | 65.1% | 276.479 | 2.78x |

Interpretation:

519.lbm_r with ref input and 8 copies causes severe degradation to TaoBench. Compared with the TaoBench-only baseline, QPS drops by about 65.1%, and P99 latency increases by about 2.78x.

This result is stronger than 505.mcf_r ref c8, which suggests that TaoBench is more sensitive to memory-bandwidth-style offline pressure than to the mcf workload under the current same-socket physical-core colocation setup.
