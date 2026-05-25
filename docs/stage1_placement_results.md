# Stage 1 Placement Results

This note summarizes the Stage 1 placement experiments for TaoBench under selected offline workloads.

Source tables:

- `docs/results/stage1_smart_repeat_level.csv`
- `docs/results/stage1_smart_aggregated.csv`

The smart summary uses nearest baseline checkpoint normalization and skips runs with invalid placement metadata or missing target-condition measurements.

## Experiment Setup

Common TaoBench settings:

- `CLIENTS_PER_THREAD=900`
- `CLIENT_TEST_TIME=60`
- `CLIENT_WARMUP_TIME=120`
- `PREWARM_ROUNDS=8`
- `PREWARM_CLIENTS=900`
- `PREWARM_TEST_TIME=60`
- `RECOVERY_PREWARM_ROUNDS=0`
- `MEASURE_REPEATS=1`

CPU and NUMA placements:

| Relation | Server cpuset | Server mems | Offline cpuset | Offline mems | Run |
|---|---|---:|---|---:|---|
| same NUMA, different cores | `0,2,4,6,8,10,12,14` | 0 | `16,18,20,22,24,26,28,30` | 0 | `stage1_place_same_numa_20260525_135210` |
| cross NUMA | `0,2,4,6,8,10,12,14` | 0 | `17,19,21,23,25,27,29,31` | 1 | `stage1_place_cross_numa_20260525_121012` |
| same SMT siblings | `0,2,4,6,8,10,12,14` | 0 | `32,34,36,38,40,42,44,46` | 0 | `stage1_place_same_smt_20260525_193324` |

The load generator used:

- `LOADGEN_CPUSET=1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47`
- `LOADGEN_MEMS=1`

## Result Tables

### Same NUMA, Different Cores

Run: `stage1_place_same_numa_20260525_135210`

| Condition | QPS | QPS degradation | P99 ms | P99 slowdown | Baseline | Status |
|---|---:|---:|---:|---:|---|---|
| `baseline_none` | 164202.46 | 0.00% | 104.959 | 1.000x | `baseline_none` | valid |
| `ibench_membw_w8` | 67576.26 | 58.79% | 239.615 | 2.294x | `baseline_after_membw` | valid |
| `baseline_after_membw` | 163989.18 | 0.00% | 104.447 | 1.000x | `baseline_after_membw` | valid |
| `ibench_l3_w8` | 70020.55 | 55.99% | 237.567 | 2.275x | `baseline_after_l3` | valid |
| `baseline_after_l3` | 159099.05 | 0.00% | 104.447 | 1.000x | `baseline_after_l3` | valid |
| `spec_mcf_ref_c8` | 117608.95 | 26.22% | 162.815 | 1.567x | `baseline_after_mcf` | valid |
| `baseline_after_mcf` | 159406.60 | 0.00% | 103.935 | 1.000x | `baseline_after_mcf` | valid |
| `spec_lbm_ref_c8` | 56551.65 | 64.52% | 286.719 | 2.759x | `baseline_after_mcf` | valid |
| `baseline_final` | 160053.45 | 0.00% | 103.935 | 1.000x | `baseline_final` | valid |

### Cross NUMA

Run: `stage1_place_cross_numa_20260525_121012`

| Condition | QPS | QPS degradation | P99 ms | P99 slowdown | Baseline | Status |
|---|---:|---:|---:|---:|---|---|
| `baseline_none` | 160136.18 | 0.00% | 103.935 | 1.000x | `baseline_none` | valid |
| `ibench_membw_w8` | 45138.00 | 71.88% | 346.111 | 3.330x | `baseline_after_membw` | valid |
| `baseline_after_membw` | 160535.21 | 0.00% | 103.935 | 1.000x | `baseline_after_membw` | valid |
| `ibench_l3_w8` | 65888.41 | 58.94% | 248.831 | 2.394x | `baseline_after_l3` | valid |
| `baseline_after_l3` | 160471.82 | 0.00% | 103.935 | 1.000x | `baseline_after_l3` | valid |
| `spec_mcf_ref_c8` | 98387.25 | 39.05% | 199.679 | 1.931x | `baseline_after_mcf` | valid |
| `baseline_after_mcf` | 161412.53 | 0.00% | 103.423 | 1.000x | `baseline_after_mcf` | valid |
| `spec_lbm_ref_c8` | 38967.43 | 75.86% | 380.927 | 3.683x | `baseline_after_mcf` | valid |
| `baseline_final` | 160905.20 | 0.00% | 103.935 | 1.000x | `baseline_final` | valid |

### Same SMT Siblings

Run: `stage1_place_same_smt_20260525_193324`

| Condition | QPS | QPS degradation | P99 ms | P99 slowdown | Baseline | Status |
|---|---:|---:|---:|---:|---|---|
| `baseline_none` | 179607.89 | 0.00% | 95.743 | 1.000x | `baseline_none` | valid |
| `ibench_membw_w8` | 63068.15 | 64.89% | 280.575 | 2.931x | `baseline_none` | valid |
| `baseline_after_membw` | 179291.77 | 0.00% | 96.255 | 1.000x | `baseline_after_membw` | valid |
| `ibench_l3_w8` | N/A | N/A | N/A | N/A | N/A | no final TaoBench stats |
| `baseline_after_l3` | 179280.49 | 0.00% | 96.255 | 1.000x | `baseline_after_l3` | valid |
| `spec_mcf_ref_c8` | 107842.53 | 39.85% | 151.551 | 1.574x | `baseline_after_l3` | valid |
| `baseline_after_mcf` | 178899.55 | 0.00% | 96.255 | 1.000x | `baseline_after_mcf` | valid |
| `spec_lbm_ref_c8` | 64619.00 | 63.88% | 276.479 | 2.872x | `baseline_after_mcf` | valid |
| `baseline_final` | 179562.50 | 0.00% | 95.743 | 1.000x | `baseline_final` | valid |

## Cross-Placement Comparison

Key workload comparison:

| Workload | Same NUMA QPS degradation | Cross NUMA QPS degradation | Same SMT QPS degradation |
|---|---:|---:|---:|
| `ibench_membw_w8` | 58.79% | 71.88% | 64.89% |
| `ibench_l3_w8` | 55.99% | 58.94% | no final stats |
| `spec_mcf_ref_c8` | 26.22% | 39.05% | 39.85% |
| `spec_lbm_ref_c8` | 64.52% | 75.86% | 63.88% |

Key latency comparison:

| Workload | Same NUMA P99 slowdown | Cross NUMA P99 slowdown | Same SMT P99 slowdown |
|---|---:|---:|---:|
| `ibench_membw_w8` | 2.294x | 3.330x | 2.931x |
| `ibench_l3_w8` | 2.275x | 2.394x | no final stats |
| `spec_mcf_ref_c8` | 1.567x | 1.931x | 1.574x |
| `spec_lbm_ref_c8` | 2.759x | 3.683x | 2.872x |

## Data Quality Notes

Valid placement runs:

- `stage1_place_same_numa_20260525_135210`: 9/9 valid measured rows.
- `stage1_place_cross_numa_20260525_121012`: 9/9 valid measured rows.
- `stage1_place_same_smt_20260525_193324`: 8/9 valid measured rows; only `ibench_l3_w8` is missing final TaoBench stats.

Excluded or diagnostic runs:

- `stage1_place_cross_numa_20260525_094609` is excluded from the cross-NUMA table because the run name says cross NUMA but recorded metadata shows `OFFLINE_MEMS=0`, so the actual placement is same NUMA.
- `stage1_place_cross_numa_fixed_20260525_104832` and `stage1_place_cross_numa_fixed_20260525_105956` have no valid measured rows.
- `stage1_place_same_smt_20260525_192402` and `stage1_place_same_smt_20260525_192427` are interrupted or empty attempts.
- `stage1_single_same_smt_ibench_l3_w8_20260525_205413` and `smoke_single_same_smt_no_prewarm_ibench_l3_w8_20260525_215718` reproduce the same `ibench_l3_w8` issue.

The `same_smt + ibench_l3_w8` issue is not a parser-only failure. In the full placement run, the single-condition retry, and the no-prewarm smoke, TaoBench/DCPerf produced no `ALL STATS`, `Gets`, or `Totals` lines and reported `dcperf_role=unknown`. iBench L3 workers were confirmed to start successfully in the single-condition retry logs. Therefore the current interpretation is that this placement/workload combination is too disruptive for TaoBench/DCPerf to emit a valid final summary under the tested settings.

## Main Takeaways

1. Same NUMA and cross NUMA placement runs are complete and usable for all selected workloads.

2. Cross NUMA is not weaker in the observed data. For the selected w8/ref-c8 points, it shows stronger degradation than same NUMA for `ibench_membw_w8`, `ibench_l3_w8`, `spec_mcf_ref_c8`, and `spec_lbm_ref_c8`.

3. Same SMT sibling placement produces valid data for `ibench_membw_w8`, `spec_mcf_ref_c8`, and `spec_lbm_ref_c8`.

4. Same SMT sibling placement with `ibench_l3_w8` should be reported as an invalid/no-final-summary point rather than imputed or recovered from progress lines.

5. For future diagnosis, use `experiments/taobench_stage1_single_condition.sh` with `RUN_BASELINES=0` and `PREWARM_ROUNDS=0` for short smoke tests. The TaoBench parser now records diagnostic fields such as `diagnostic_status`, `dcperf_role`, and the last observed progress line when final stats are missing.
