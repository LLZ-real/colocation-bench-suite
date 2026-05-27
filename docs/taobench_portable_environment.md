# TaoBench Portable Docker Environment

This note describes how to package the working DCPerf/TaoBench environment into
one Docker image so a new server only needs the image plus `conf/env.sh`
placement settings.

## Build On The Source Server

The build script copies the local DCPerf tree into a temporary Docker build
context and excludes historical run output:

- `benchmark_metrics_*/`
- `results/`
- `*.log`
- Python caches and `.git/`

Build the ready image:

```bash
bash scripts/build_taobench_image.sh
```

If the server needs an HTTP proxy for apt/pip during Docker build:

```bash
PROXY="http://127.0.0.1:7900" bash scripts/build_taobench_image.sh
```

The build script uses Docker host networking by default, so a localhost proxy on
the host is visible to the build container. It also defaults to:

```text
APT_MIRROR=http://mirrors.aliyun.com/ubuntu
```

Override it when needed:

```bash
APT_MIRROR=http://mirrors.tuna.tsinghua.edu.cn/ubuntu \
PROXY="http://127.0.0.1:7900" \
bash scripts/build_taobench_image.sh
```

Default image:

```text
dcperf-taobench:ready
```

The image contains:

- DCPerf under `/workspace/DCPerf`
- TaoBench benchmark and package directories
- benchpress Python dependencies
- OpenSSL runtime/development libraries
- Ubuntu `libgflags-dev` / `libgflags2.2` packages, version 2.2.2 on Ubuntu 22.04

Optional overrides:

```bash
IMAGE_NAME=dcperf-taobench IMAGE_TAG=ready \
DCPERF_DIR=/path/to/DCPerf \
bash scripts/build_taobench_image.sh
```

## Export And Transfer

```bash
bash scripts/export_taobench_image.sh dcperf-taobench-ready.tar
scp dcperf-taobench-ready.tar lilinzhen@sail3090:~
```

## Import On A New Server

```bash
ssh lilinzhen@sail3090
bash scripts/import_taobench_image.sh ~/dcperf-taobench-ready.tar
python3 application/generate_env_from_topology.py --offline-policy same_smt --out conf/env.sh
vim conf/env.sh
bash application/preflight.sh
bash tools/check_sail3090_topology.sh
```

For the portable image path, set these in `conf/env.sh`:

```bash
export CLAB_IMAGE="dcperf-taobench:ready"
export DCPERF_MOUNT="0"
```

`DCPERF_MOUNT=0` tells the container creation scripts to use the image-baked
`/workspace/DCPerf` instead of mounting a host DCPerf checkout.

You still need host paths for data that should remain outside the image:

```bash
export RESULTS_ROOT="/home/lilinzhen/colocate_lab/results/cbs"
export IBENCH_DIR="/home/lilinzhen/iBench"
export SPEC_DIR="/home/lilinzhen/cpu2017"
```

CPU and NUMA placement remains server-specific:

```bash
export SERVER_CPUSET="0,2,4,6,8,10,12,14"
export SERVER_MEMS="0"
export LOADGEN_CPUSET="1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47"
export LOADGEN_MEMS="1"
export OFFLINE_CPUSET="32,34,36,38,40,42,44,46"
export OFFLINE_MEMS="0"
```

## Compatibility Mode

If you want to keep using a host DCPerf checkout, leave:

```bash
export DCPERF_MOUNT="1"
export DCPERF_DIR="/home/lilinzhen/colocate_lab/DCPerf"
```

The same `dcperf-taobench:ready` image can still run with host-mounted DCPerf;
the mount simply overlays `/workspace/DCPerf`.

## Smoke Checks

After import:

```bash
docker run --rm dcperf-taobench:ready bash -lc 'cd /workspace/DCPerf && ./benchpress_cli.py list | grep tao_bench'
```

Then create containers with a short dry run or smoke run from the benchmark
scripts. The TaoBench server/client launchers continue to use
`/workspace/DCPerf` inside the container.
