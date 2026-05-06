# Colocation Bench Suite

A lightweight automation framework for colocation interference experiments.

Current focus:

- TaoBench as the online workload
- iBench as the offline interference workload
- Docker cpuset/NUMA isolation
- Structured result collection
- Stable request-driven prewarm before measurement

## Current methodology

TaoBench is sensitive to cold start and request-driven warmup. Therefore, all measured runs should use a fixed prewarm phase before collecting performance metrics.

Current stable online load:

- `clients_per_thread=900`
- `PREWARM_CLIENTS=900`
- `PREWARM_ROUNDS=8`
- `CLIENT_TEST_TIME=300` for formal experiments
- `ENABLE_PERF=0` for primary performance measurements

PMU/perf profiling is treated as a separate analysis task because perf collection can perturb TaoBench performance.

## Repository layout

```text
conf/          Local configuration templates
containers/    Docker container lifecycle scripts
online/        Online workload launchers
offline/       Offline workload launchers
collectors/    PMU/perf collectors
parsers/       Log parsers
experiments/   End-to-end experiment scripts
docs/          Notes and reports
results/       Placeholder only; real results are ignored
```

## Setup

```bash
cp conf/env.example.sh conf/env.sh
vim conf/env.sh
```

**Required external paths:**

- DCPerf
- iBench
- Docker image: `clab-compute:latest`

## TaoBench stable baseline

```bash
ENABLE_PERF=0 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
CLIENT_LIST="900 900 900" \
CLIENT_TEST_TIME=60 \
bash experiments/taobench_baseline_curve.sh
```

## Week 2 TaoBench + iBench experiment

### Baseline:

```bash
EXP_NAME=week2_taobench_baseline \
OFFLINE_TYPE=none \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=300 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
bash experiments/taobench_ibench_one.sh
```

### Memory bandwidth interference:

```bash
IBENCH_MEMBW_ARG=30 \
EXP_NAME=week2_taobench_ibench_membw \
OFFLINE_TYPE=ibench_membw \
OFFLINE_PARAM=8 \
CLIENTS_PER_THREAD=900 \
CLIENT_TEST_TIME=300 \
SERVER_BOOTSTRAP_WAIT=180 \
PREWARM_ROUNDS=8 \
PREWARM_CLIENTS=900 \
PREWARM_TEST_TIME=60 \
bash experiments/taobench_ibench_one.sh
```

## Notes

External benchmark suites and large result files are not committed. Configure their locations through `conf/env.sh`.