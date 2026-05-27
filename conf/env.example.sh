#!/usr/bin/env bash

# Root of this repository
export CBS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# External dependencies on host
export DCPERF_DIR="/home/lilinzhen/colocate_lab/DCPerf"
export RESULTS_ROOT="/home/lilinzhen/colocate_lab/results/cbs"

# Docker image
# For portable TaoBench/DCPerf migration, use:
#   export CLAB_IMAGE="dcperf-taobench:ready"
#   export DCPERF_MOUNT="0"
export CLAB_IMAGE="clab-compute:latest"
export DCPERF_MOUNT="${DCPERF_MOUNT:-1}"

# Container names
export SERVER_CONTAINER="clab-server"
export LOADGEN_CONTAINER="clab-loadgen"

# CPU / NUMA placement
export SERVER_CPUSET="${SERVER_CPUSET:-0,2,4,6,8,10,12,14}"
export SERVER_MEMS="${SERVER_MEMS:-0}"

export LOADGEN_CPUSET="${LOADGEN_CPUSET:-1,3,5,7,9,11,13,15,33,35,37,39,41,43,45,47}"
export LOADGEN_MEMS="${LOADGEN_MEMS:-1}"

# TaoBench default params
export TAO_MEMSIZE="16"
export TAO_SERVER_PORT="11211"
export TAO_INTERFACE_NAME="eno1"

# Network / system tuning
export ULIMIT_NOFILE="65535"
export TAO_SERVER_PID_PATTERN="tao_bench_server"

export OFFLINE_CONTAINER="clab-offline"
export OFFLINE_CPUSET="${OFFLINE_CPUSET:-16,18,20,22,24,26,28,30}"
export OFFLINE_MEMS="${OFFLINE_MEMS:-0}"
export IBENCH_DIR="/home/lilinzhen/iBench"
export SPEC_DIR="/home/lilinzhen/cpu2017"
