# Weekly Report: Stage 1 TaoBench Colocation Experiments

## Goal

This week focuses on Stage 1 of the colocation benchmark plan: fixing TaoBench as the online workload and characterizing how different offline workloads affect its QPS and tail latency.

## Experiment Setup

- Online workload: TaoBench
- Online clients_per_thread: 900
- Main metrics: QPS and P99 latency
- Baseline: TaoBench only
- Synthetic offline workloads: iBench CPU, iBench memBw, iBench L3
- Real offline workloads: SPEC CPU2017 505.mcf_r and 519.lbm_r
- Placement: TaoBench server and offline workloads are colocated on the same socket but different physical cores; load generator is placed on the other socket.

## Baseline

TaoBench stable baseline:

- QPS: 165508.28
- P99 latency: 99.327 ms

## Key Results

### iBench synthetic interference

CPU-only interference has little impact under the current placement because the online and offline workloads do not share physical cores or SMT sibling threads.

Memory bandwidth and L3/cache interference cause significant degradation:

- iBench memBw w8: QPS drops by 58.6%, P99 slowdown is 2.34x.
- iBench L3 w8: QPS drops by 55.4%, P99 slowdown is 2.20x.

### SPEC CPU real offline workloads

SPEC CPU2017 has been integrated as a real offline workload.

For 505.mcf_r:

- ref c2: QPS degradation 6.2%, P99 slowdown 1.06x.
- ref c4: QPS degradation 11.2%, P99 slowdown 1.11x.
- ref c8: QPS degradation 29.3%, P99 slowdown 1.51x.
- ref c8 repeat: QPS degradation 31.3%, P99 slowdown 1.56x.

For 519.lbm_r:

- ref c2: QPS degradation 13.8%, P99 slowdown 1.14x.
- ref c4: QPS degradation 42.2%, P99 slowdown 1.68x.
- ref c8: QPS degradation 65.1%, P99 slowdown 2.78x.
- ref c8 repeat: QPS degradation 66.0%, P99 slowdown 2.87x.

## Interpretation

The results show that TaoBench is much more sensitive to memory-bandwidth and cache-related pressure than to CPU-only pressure under physical-core isolation.

SPEC lbm causes much stronger degradation than SPEC mcf, especially as the number of copies increases. This suggests that the resource fingerprint of the offline workload strongly affects online slowdown.

The repeated c8 experiments confirm that the observed degradation is stable.

## Current Stage 1 Status

Completed:

- Stable TaoBench baseline.
- iBench CPU/memBw/L3 integration.
- SPEC CPU2017 mcf/lbm integration.
- SPEC copies gradient for c2/c4/c8.
- Repeat experiments for mcf/lbm ref c8.
- Clean summary table and plots.

Deferred:

- MediaWiki. It is important for workload diversity but currently blocked by the generic HHVM/oss-performance runner path. It is deferred to avoid blocking the TaoBench-centered Stage 1 pipeline.

## Next Steps

1. Add PMU/perf counters for representative points:
   - baseline
   - iBench memBw w8
   - iBench L3 w8
   - SPEC mcf ref c8
   - SPEC lbm ref c8

2. Build an offline workload fingerprint table:
   - CPU pressure
   - memory bandwidth pressure
   - LLC/cache pressure
   - QPS degradation
   - P99 slowdown

3. Use the current Stage 1 results to motivate a simple slowdown model:
   - input: offline workload type/intensity/fingerprint
   - output: TaoBench QPS degradation and P99 slowdown

