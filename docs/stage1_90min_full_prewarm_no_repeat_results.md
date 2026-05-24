# Stage 1 Fast Gradient Scan: TaoBench Colocation

## Experiment

This run is a fast Stage 1 gradient scan for TaoBench colocation.

The goal is to cover as many offline workload intensity gradients as possible within about 1.5 hours, without repeat runs.

## Command

```bash
EXP_NAME=stage1_90min_full_prewarm_no_repeat \
SERVER_BOOTSTRAP_WAIT=180 \
TAO_SERVER_WARMUP_TIME=2400 \
TAO_SERVER_TEST_TIME=10800 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
RECOVERY_PREWARM_ROUNDS=0 \
RECOVERY_PREWARM_TEST_TIME=0 \
CLIENTS_PER_THREAD=900 \
CLIENT_WARMUP_TIME=120 \
CLIENT_TEST_TIME=60 \
MEASURE_REPEATS=1 \
MEASURE_GAP=0 \
OFFLINE_COOLDOWN_WAIT=5 \
OFFLINE_STABILIZE_WAIT=20 \
SPEC_CONFIG=my_test.cfg \
bash experiments/taobench_stage1_recovery_matrix.sh
```

## Run Directory

```text
/home/lilinzhen/colocate_lab/results/cbs/stage1_90min_full_prewarm_no_repeat_20260524_230354
```

## Prewarm Stability

The first several prewarm rounds were still warming up, but rounds 6 to 8 reached a stable TaoBench baseline.

| Prewarm Round | QPS | P99 ms |
|---:|---:|---:|
| 1 | 29739.10 | 354.303 |
| 2 | 36779.47 | 327.679 |
| 3 | 47674.10 | 292.863 |
| 4 | 68898.58 | 219.135 |
| 5 | 111361.70 | 147.455 |
| 6 | 167778.02 | 97.279 |
| 7 | 167320.51 | 97.791 |
| 8 | 167013.19 | 97.791 |

This confirms that the 8-round prewarm was necessary and sufficient for this run.

## Baseline

The baseline checkpoints were stable throughout the experiment.

| Checkpoint | QPS | P99 ms |
|---|---:|---:|
| baseline_none | 166694.23 | 97.791 |
| baseline_after_membw | 166751.71 | 97.791 |
| baseline_after_l3 | 167262.31 | 97.791 |
| baseline_after_mcf | 166706.14 | 97.791 |
| baseline_final | 166714.79 | 97.791 |

The average baseline used for degradation calculation is:

```text
QPS = 166825.84
P99 = 97.791 ms
```

## Results

| Condition | QPS | QPS Degradation | P99 ms | P99 Slowdown |
|---|---:|---:|---:|---:|
| ibench_cpu_w8 | 166607.64 | 0.13% | 97.791 | 1.00x |
| ibench_membw_w2 | 150923.56 | 9.53% | 106.495 | 1.09x |
| ibench_membw_w4 | 109800.06 | 34.18% | 146.431 | 1.50x |
| ibench_membw_w8 | 69587.24 | 58.29% | 231.423 | 2.37x |
| ibench_l3_w2 | 143943.48 | 13.72% | 112.639 | 1.15x |
| ibench_l3_w4 | 92737.33 | 44.41% | 174.079 | 1.78x |
| ibench_l3_w8 | 75716.84 | 54.61% | 218.111 | 2.23x |
| spec_mcf_ref_c2 | 159582.86 | 4.34% | 101.375 | 1.04x |
| spec_mcf_ref_c4 | 148293.52 | 11.11% | 108.031 | 1.10x |
| spec_mcf_ref_c8 | 122542.17 | 26.54% | 146.431 | 1.50x |
| spec_lbm_ref_c2 | 143514.52 | 13.97% | 111.615 | 1.14x |
| spec_lbm_ref_c4 | 96334.77 | 42.25% | 166.911 | 1.71x |
| spec_lbm_ref_c8 | 59903.95 | 64.09% | 268.287 | 2.74x |

## Observations

1. CPU-only interference has almost no impact under the current CPU placement.
2. iBench memory bandwidth interference shows a clear monotonic degradation trend.
3. iBench L3 interference also shows a clear monotonic degradation trend.
4. SPEC mcf causes moderate real-workload interference.
5. SPEC lbm causes the strongest real-workload interference and behaves similarly to memory-bandwidth pressure.
6. Baseline checkpoints remained stable, so the no-repeat fast scan did not show significant long-term TaoBench drift.

## Recommended Follow-up

Repeat only the most informative points:

```text
baseline_none
ibench_membw_w8
ibench_l3_w8
spec_mcf_ref_c8
spec_lbm_ref_c8
```

If more time is available, also repeat:

```text
ibench_membw_w4
ibench_l3_w4
spec_lbm_ref_c4
```
