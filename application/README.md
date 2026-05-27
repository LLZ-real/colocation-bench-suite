# Application Experiment Harness

This directory contains a portable, parameter-driven harness for future
colocation experiments. It is intentionally separate from `experiments/` so the
current Stage 1 scripts remain stable.

Goals:

- Discover host CPU, NUMA, and cache topology.
- Select TaoBench server/loadgen cpusets and offline workload cpusets.
- Create Docker containers with configurable cgroup, cpuset, memory, network,
  blkio, and CPU quota settings.
- Keep hooks for Intel RDT CAT/LLC allocation, Intel MBA, CPU memory capacity,
  network shaping, disk IO shaping, and CPU frequency control.
- Reuse existing TaoBench, iBench, and SPEC launchers where possible.

## Quick Start

Show host topology:

```bash
python3 application/topology.py --format text
python3 application/topology.py --format json
```

Generate a starter `conf/env.sh` from the current host topology:

```bash
python3 application/generate_env_from_topology.py \
  --offline-policy same_smt \
  --out conf/env.sh
```

For the portable TaoBench image, keep:

```bash
export CLAB_IMAGE="dcperf-taobench:ready"
export DCPERF_MOUNT="0"
```

If the server will build the portable image locally and does not yet have a
DCPerf checkout, bootstrap it first:

```bash
PROXY="http://127.0.0.1:7900" \
DCPERF_DIR="/home/lilinzhen/colocate_lab/DCPerf" \
bash application/bootstrap_dcperf_taobench.sh
```

Run a migration/preflight check:

```bash
bash application/preflight.sh
```

Check a generated env before replacing `conf/env.sh`:

```bash
python3 application/generate_env_from_topology.py --offline-policy cross_numa --out /tmp/cbs-env.sh
ENV_FILE=/tmp/cbs-env.sh CHECK_OFFLINE_PATHS=0 bash application/preflight.sh
```

Preview a same-SMT TaoBench + iBench L3 run without starting containers:

```bash
ACTION=dry-run \
EXP_NAME=app_smoke_same_smt_l3 \
SERVER_CPUSET=0,2,4,6,8,10,12,14 SERVER_MEMS=0 \
LOADGEN_CPUSET=1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47 LOADGEN_MEMS=1 \
OFFLINE_CPUSET=32,34,36,38,40,42,44,46 OFFLINE_MEMS=0 \
OFFLINE_TYPE=ibench_l3 OFFLINE_PARAM=8 OFFLINE_LABEL=w8 \
bash application/run_taobench_colocation.sh
```

Run for real:

```bash
ACTION=run \
EXP_NAME=app_same_smt_l3 \
SERVER_CPUSET=0,2,4,6,8,10,12,14 SERVER_MEMS=0 \
LOADGEN_CPUSET=1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47 LOADGEN_MEMS=1 \
OFFLINE_CPUSET=32,34,36,38,40,42,44,46 OFFLINE_MEMS=0 \
OFFLINE_TYPE=ibench_l3 OFFLINE_PARAM=8 OFFLINE_LABEL=w8 \
bash application/run_taobench_colocation.sh
```

## Key Parameters

Placement:

- `SERVER_CPUSET`, `SERVER_MEMS`
- `LOADGEN_CPUSET`, `LOADGEN_MEMS`
- `OFFLINE_CPUSET`, `OFFLINE_MEMS`

Offline workload:

- `OFFLINE_TYPE=none|ibench_cpu|ibench_membw|ibench_l3|ibench_memcap|spec_mcf|spec_lbm`
- `OFFLINE_PARAM`
- `OFFLINE_LABEL`
- `SPEC_SIZE`, `SPEC_COPIES`, `SPEC_CONFIG`

Cgroup and Docker resource controls:

- `CGROUP_MODE=docker|systemd|none`
- `SERVER_CGROUP_PARENT`, `LOADGEN_CGROUP_PARENT`, `OFFLINE_CGROUP_PARENT`
- `SERVER_CPU_SHARES`, `LOADGEN_CPU_SHARES`, `OFFLINE_CPU_SHARES`
- `SERVER_CPU_QUOTA`, `LOADGEN_CPU_QUOTA`, `OFFLINE_CPU_QUOTA`
- `SERVER_MEMORY_LIMIT`, `LOADGEN_MEMORY_LIMIT`, `OFFLINE_MEMORY_LIMIT`
- `SERVER_BLKIO_WEIGHT`, `LOADGEN_BLKIO_WEIGHT`, `OFFLINE_BLKIO_WEIGHT`
- `OFFLINE_DEVICE_READ_BPS`, `OFFLINE_DEVICE_WRITE_BPS`

Reserved resource hooks:

- Intel LLC/CAT: `RDT_ENABLE=1`, `SERVER_LLC_MASK`, `LOADGEN_LLC_MASK`, `OFFLINE_LLC_MASK`
- Intel MBA: `MBA_ENABLE=1`, `SERVER_MBA_PERCENT`, `LOADGEN_MBA_PERCENT`, `OFFLINE_MBA_PERCENT`
- Network: `NET_SHAPE_ENABLE=1`, `NET_IFACE`, `OFFLINE_NET_RATE`, `LOADGEN_NET_RATE`
- CPU frequency: `CPU_FREQ_ENABLE=1`, `CPU_FREQ_GOVERNOR`, `CPU_FREQ_MIN`, `CPU_FREQ_MAX`

The reserved hooks are dry-run safe by default. They log intent and only apply
when the matching enable variable is set.

`OFFLINE_WORKLOAD` is accepted as an alias for `OFFLINE_TYPE` so commands can
read naturally in experiment notes.

## Migration Flow

On a new server:

```bash
# Option A: import a prebuilt image.
bash scripts/import_taobench_image.sh dcperf-taobench-ready.tar

# Option B: build locally from a cloned/installed DCPerf checkout.
bash application/bootstrap_dcperf_taobench.sh

python3 application/generate_env_from_topology.py --offline-policy same_smt --out conf/env.sh
vim conf/env.sh
bash application/preflight.sh
ACTION=dry-run bash application/run_taobench_colocation.sh
```

The generated env is only a starting point. Review network interface,
`RESULTS_ROOT`, `IBENCH_DIR`, `SPEC_DIR`, and all CPU/NUMA bindings before a long
experiment.
