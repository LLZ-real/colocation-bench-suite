#!/usr/bin/env bash

# Root of this repository
export CBS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# External dependencies on host
export DCPERF_DIR="/home/lilinzhen/colocate_lab/DCPerf"
export RESULTS_ROOT="/home/lilinzhen/colocate_lab/results/cbs"

# Docker image
export CLAB_IMAGE="clab-compute:latest"

# Container names
export SERVER_CONTAINER="clab-server"
export LOADGEN_CONTAINER="clab-loadgen"

# CPU / NUMA placement
export SERVER_CPUSET="0,2,4,6,8,10,12,14"
export SERVER_MEMS="0"

export LOADGEN_CPUSET="1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31"
export LOADGEN_MEMS="1"

# TaoBench default params
export TAO_MEMSIZE="16"
export TAO_SERVER_PORT="11211"
export TAO_INTERFACE_NAME="eno1"

# Network / system tuning
export ULIMIT_NOFILE="65535"
export TAO_SERVER_PID_PATTERN="tao_bench_server"
