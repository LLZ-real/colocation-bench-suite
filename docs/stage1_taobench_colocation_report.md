# Stage 1 Report: TaoBench-Centered Colocation Experiments

## 1. Goal

Stage 1 fixes TaoBench as the online workload and studies how different offline workloads affect online performance under controlled colocation.

The main goal is to build an offline workload characterization pipeline and observe the relation between offline resource pressure and TaoBench slowdown.

## 2. Experiment setup

Online workload:

- TaoBench

Offline workloads:

- iBench CPU
- iBench memBw
- iBench L3
- SPEC CPU2017 505.mcf_r
- SPEC CPU2017 519.lbm_r

Main metrics:

- QPS
- P99 latency
- QPS degradation
- P99 slowdown

Stable baseline:

- QPS: 165508.28
- P99 latency: 99.327 ms

Placement:

- TaoBench server and offline workloads are placed on the same socket but different physical cores.
- TaoBench load generator is placed on the other socket.

## 3. Synthetic interference results

iBench CPU has little effect under the current placement:

- iBench CPU w8: QPS degradation -0.4%, P99 slowdown 0.99x.
- iBench CPU w30: QPS degradation 0.5%, P99 slowdown 1.00x.

This is expected because the online and offline workloads do not share the same physical core or SMT sibling threads.

iBench memBw causes strong degradation:

- w2: QPS degradation 8.9%, P99 slowdown 1.08x.
- w4: QPS degradation 34.7%, P99 slowdown 1.49x.
- w8: QPS degradation 58.6%, P99 slowdown 2.34x.

iBench L3 also causes strong degradation:

- w2: QPS degradation 13.8%, P99 slowdown 1.14x.
- w4: QPS degradation 44.1%, P99 slowdown 1.74x.
- w8: QPS degradation 55.4%, P99 slowdown 2.20x.

These results indicate that TaoBench is sensitive to memory bandwidth and LLC/cache pressure.

## 4. SPEC CPU2017 results

SPEC CPU2017 is integrated as a real offline workload.

### 505.mcf_r

- train c1: QPS degradation 1.5%, P99 slowdown 1.01x.
- ref c2: QPS degradation 6.2%, P99 slowdown 1.06x.
- ref c4: QPS degradation 11.2%, P99 slowdown 1.11x.
- ref c8: QPS degradation 29.3%, P99 slowdown 1.51x.
- ref c8 repeat: QPS degradation 31.3%, P99 slowdown 1.56x.

The train c1 run is too weak and mainly serves as a smoke test. The ref c8 run causes stable moderate interference.

### 519.lbm_r

- ref c2: QPS degradation 13.8%, P99 slowdown 1.14x.
- ref c4: QPS degradation 42.2%, P99 slowdown 1.68x.
- ref c8: QPS degradation 65.1%, P99 slowdown 2.78x.
- ref c8 repeat: QPS degradation 66.0%, P99 slowdown 2.87x.

519.lbm_r causes much stronger degradation than 505.mcf_r, especially at c4 and c8. This is consistent with lbm behaving like a memory-bandwidth-intensive workload.

## 5. Key findings

1. CPU-only interference is weak under physical-core isolation.

2. Memory bandwidth and LLC/cache interference strongly affect TaoBench.

3. Real offline workloads can reproduce significant online slowdown.

4. Different SPEC workloads cause different degrees of interference.

5. Increasing offline intensity, represented by SPEC copies, leads to stronger TaoBench degradation.

6. Repeat experiments confirm that the c8 results are stable.

## 6. Limitations

1. Only one online workload is currently used.

   MediaWiki was investigated but deferred because the current blocker is in the generic HHVM / oss-performance runner path.

2. PMU counters are not yet included in the main result table.

   The next step is to collect PMU metrics for representative points and connect microarchitectural behavior with observed slowdown.

3. The current placement is fixed.

   Same-socket but different physical cores are used. Cross-socket and SMT-sharing configurations are not yet evaluated.

## 7. Next steps

1. Collect PMU/perf metrics for representative points:

   - baseline
   - iBench memBw w8
   - iBench L3 w8
   - SPEC mcf ref c8
   - SPEC lbm ref c8

2. Build an offline fingerprint table:

   - expected resource pressure
   - QPS degradation
   - P99 slowdown
   - PMU metrics

3. Develop a simple slowdown model:

   - input: offline workload type and intensity
   - output: QPS degradation and P99 slowdown

4. Revisit MediaWiki after the TaoBench-centered Stage 1 pipeline is stable.

