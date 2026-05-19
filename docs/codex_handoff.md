# Codex Handoff: Colocation Benchmark Suite

## 0. Read this first

This project is a TaoBench-centered colocation benchmark suite.

The current focus is NOT MediaWiki.
The current focus is TaoBench + iBench / SPEC CPU offline workloads.

MediaWiki is important for long-term workload diversity, but it is currently deferred because the failure is in the generic oss-performance / HHVM runner path. Do not debug MediaWiki unless explicitly asked.

## 1. Project goal

Build a benchmark suite to evaluate how offline workloads affect TaoBench online performance under controlled colocation.

Primary online workload:

- TaoBench

Current offline workloads:

- iBench synthetic workloads:
  - ibench_cpu
  - ibench_membw
  - ibench_l3
  - ibench_memcap, but do not run it unless explicitly asked because it may cause OOM

- SPEC CPU2017 real workloads:
  - spec_mcf -> 505.mcf_r
  - spec_lbm -> 519.lbm_r

## 2. Important paths

Repository:

- /home/lilinzhen/colocation-bench-suite

Results root:

- /home/lilinzhen/colocate_lab/results/cbs

SPEC CPU2017:

- /home/lilinzhen/cpu2017

iBench:

- /home/lilinzhen/iBench

Main experiment script:

- experiments/taobench_colocation_one.sh

Legacy wrapper:

- experiments/taobench_ibench_one.sh

The legacy wrapper should remain for backward compatibility.

## 3. Critical parameter semantics

Do not confuse OFFLINE_PARAM and OFFLINE_LABEL.

OFFLINE_PARAM:

- Real runtime parameter passed to the offline workload.
- For iBench, this is important.
- Example:
  OFFLINE_TYPE=ibench_membw
  OFFLINE_PARAM=8
- This means start iBench memBw with parameter 8.

OFFLINE_LABEL:

- Human-readable label for run directory, log name, and summary.
- It must not be used as the runtime argument for iBench.
- Example:
  OFFLINE_LABEL=w8

For SPEC:

- OFFLINE_PARAM is usually empty.
- SPEC_SIZE and SPEC_COPIES control the actual SPEC workload.
- OFFLINE_LABEL records the semantic label.

Example SPEC setting:

- OFFLINE_TYPE=spec_lbm
- SPEC_SIZE=ref
- SPEC_COPIES=8
- OFFLINE_LABEL=ref_c8

Never rewrite OFFLINE_PARAM just to make summary labels prettier, because it may change iBench behavior.

## 4. Current stable baseline

TaoBench baseline:

- clients_per_thread: 900
- QPS: about 165k to 167k
- P99: about 98 to 100 ms

Reference baseline currently used:

- QPS = 165508.28
- P99 = 99.327 ms

## 5. Current results

### Week 2: iBench

Baseline:

- offline_type: none
- offline_label: none
- QPS: 165508.28
- P99: 99.327 ms

iBench CPU:

- ibench_cpu, OFFLINE_PARAM=30, OFFLINE_LABEL=w30
  - QPS: 164615.12
  - P99: 99.327 ms
  - Interpretation: weak effect because offline workload is on different physical cores.

- ibench_cpu, OFFLINE_PARAM=8, OFFLINE_LABEL=w8
  - QPS: 166133.17
  - P99: 98.303 ms
  - Interpretation: weak effect because offline workload is on different physical cores.

iBench memory bandwidth:

- ibench_membw, OFFLINE_PARAM=2, OFFLINE_LABEL=w2
  - QPS: 150847.49
  - P99: 107.007 ms

- ibench_membw, OFFLINE_PARAM=4, OFFLINE_LABEL=w4
  - QPS: 108052.41
  - P99: 148.479 ms

- ibench_membw, OFFLINE_PARAM=8, OFFLINE_LABEL=w8
  - QPS: 68547.89
  - P99: 232.447 ms

- ibench_membw, OFFLINE_PARAM=8, OFFLINE_LABEL=w8_repeat
  - QPS: 66628.93
  - P99: 239.615 ms

iBench L3:

- ibench_l3, OFFLINE_PARAM=2, OFFLINE_LABEL=w2
  - QPS: 142615.00
  - P99: 113.151 ms

- ibench_l3, OFFLINE_PARAM=4, OFFLINE_LABEL=w4
  - QPS: 92445.59
  - P99: 173.055 ms

- ibench_l3, OFFLINE_PARAM=8, OFFLINE_LABEL=w8
  - QPS: 73893.81
  - P99: 218.111 ms

Main Week 2 interpretation:

- CPU-only interference has little effect under current physical-core isolation.
- Memory bandwidth and L3/cache interference significantly degrade TaoBench.

## 6. Week 3: SPEC CPU2017

SPEC mcf train, 1 copy:

- offline_type: spec_mcf
- SPEC benchmark: 505.mcf_r
- SPEC_SIZE=train
- SPEC_COPIES=1
- OFFLINE_LABEL=train_c1
- QPS: 162973.17
- P99: 100.351 ms
- Interpretation: too weak; useful only as smoke/pipeline validation.

SPEC mcf ref, 8 copies:

- offline_type: spec_mcf
- SPEC benchmark: 505.mcf_r
- SPEC_SIZE=ref
- SPEC_COPIES=8
- OFFLINE_LABEL=ref_c8
- QPS: 116962.26
- P99: 149.503 ms
- QPS degradation: about 29.3%
- P99 slowdown: about 1.51x
- Interpretation: moderate real-workload interference.

SPEC lbm ref, 8 copies:

- offline_type: spec_lbm
- SPEC benchmark: 519.lbm_r
- SPEC_SIZE=ref
- SPEC_COPIES=8
- OFFLINE_LABEL=ref_c8
- QPS: 57720.51
- P99: 276.479 ms
- QPS degradation: about 65.1%
- P99 slowdown: about 2.78x
- Interpretation: severe degradation; likely memory-bandwidth-style interference.

Main Week 3 interpretation:

- SPEC CPU has been successfully integrated as a real offline workload.
- train + 1 copy is too weak.
- ref + 8 copies produces meaningful interference.
- lbm ref c8 is much stronger than mcf ref c8, consistent with TaoBench sensitivity to memory bandwidth pressure.

## 7. MediaWiki status

MediaWiki is deferred.

Recovered components:

- HHVM 3.30.12 can run ordinary PHP.
- HHVM legacy mysql extension works.
- MariaDB, Nginx, wrk, and memcached are available.
- mw_bench database can be created and imported.
- HHVM can connect to mw_bench and query tables.

Remaining failure:

- perf.php --mediawiki-mlp segfaults.
- perf.php --mediawiki also segfaults.
- perf.php --toys-hello-world also segfaults.

Interpretation:

Because toys-hello-world also segfaults, the current failure is not specific to MediaWiki DB or MediaWiki target. It is likely in the generic oss-performance / HHVM runner path.

Do not debug MediaWiki unless explicitly asked.

## 8. Current next tasks

Priority 1: Stabilize Week 3 results.

Run repeat experiments:

1. SPEC lbm ref c8 repeat
2. SPEC mcf ref c8 repeat

Command for lbm repeat:

SPEC_CONFIG=my_test.cfg \
SPEC_SIZE=ref \
SPEC_COPIES=8 \
OFFLINE_LABEL=ref_c8_repeat \
EXP_NAME=week3_taobench_spec_lbm_ref_c8_repeat \
OFFLINE_TYPE=spec_lbm \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=300 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
bash experiments/taobench_colocation_one.sh

Command for mcf repeat:

SPEC_CONFIG=my_test.cfg \
SPEC_SIZE=ref \
SPEC_COPIES=8 \
OFFLINE_LABEL=ref_c8_repeat \
EXP_NAME=week3_taobench_spec_mcf_ref_c8_repeat \
OFFLINE_TYPE=spec_mcf \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=300 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
bash experiments/taobench_colocation_one.sh

Priority 2: Add SPEC copies gradient.

Recommended grid:

- spec_mcf ref c2
- spec_mcf ref c4
- spec_mcf ref c8
- spec_lbm ref c2
- spec_lbm ref c4
- spec_lbm ref c8

Use:

- SPEC_COPIES=2 and OFFLINE_LABEL=ref_c2
- SPEC_COPIES=4 and OFFLINE_LABEL=ref_c4
- SPEC_COPIES=8 and OFFLINE_LABEL=ref_c8

Priority 3: Improve summary tooling.

Create or update a summary script that outputs:

- phase
- offline_type
- offline_param
- offline_label
- clients_per_thread
- qps
- qps_degradation_pct
- gets_p99_ms
- p99_slowdown
- run_dir
- notes

The script must support both old and new summary.csv formats.

Old summary format:

- offline_type
- offline_param
- clients_per_thread
- qps
- gets_p99_ms
- client_log
- offline_log

New summary format:

- offline_type
- offline_param
- offline_label
- clients_per_thread
- qps
- gets_p99_ms
- client_log
- offline_log

For old rows, use offline_label = row.get("offline_label") or row.get("offline_param") or "".

Priority 4: Documentation.

Update:

- docs/week2_ibench_results.md
- docs/week3_spec_results.md
- docs/colocation_results_new_format.csv

## 9. Do not do unless explicitly asked

- Do not continue MediaWiki debugging.
- Do not run ibench_memcap as a formal experiment.
- Do not enable perf/PMU in primary performance runs yet.
- Do not change CPU placement.
- Do not change OFFLINE_PARAM semantics.
- Do not delete old result directories.
- Do not rewrite the whole repository.

## 10. First Codex task

Read this file first.

Then:

1. Inspect experiments/taobench_colocation_one.sh.
2. Inspect experiments/taobench_ibench_one.sh.
3. Verify OFFLINE_PARAM is only used as runtime parameter.
4. Verify OFFLINE_LABEL is only used for labels, run directory names, log names, and summary.
5. Inspect tools/summarize_week2.py and tools/summarize_week3.py if present.
6. Propose a plan before making changes.
7. Do not run long experiments yet.
