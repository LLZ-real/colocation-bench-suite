#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

# Defaults, can be overridden in conf/env.sh or command line.
OFFLINE_CONTAINER="${OFFLINE_CONTAINER:-clab-offline}"
OFFLINE_CPUSET="${OFFLINE_CPUSET:-16,18,20,22,24,26,28,30}"
OFFLINE_MEMS="${OFFLINE_MEMS:-0}"

IBENCH_DIR="${IBENCH_DIR:-/home/lilinzhen/iBench}"
SPEC_DIR="${SPEC_DIR:-/home/lilinzhen/cpu2017}"
RESULTS_ROOT="${RESULTS_ROOT:-/home/lilinzhen/colocate_lab/results/cbs}"
CLAB_IMAGE="${CLAB_IMAGE:-clab-compute:latest}"

log "Removing old ${OFFLINE_CONTAINER} if exists..."
docker rm -f "${OFFLINE_CONTAINER}" 2>/dev/null || true

log "Creating ${OFFLINE_CONTAINER}..."
docker run -d --init --name "${OFFLINE_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${OFFLINE_CPUSET}" \
  --cpuset-mems="${OFFLINE_MEMS}" \
  -v "${IBENCH_DIR}:/workspace/iBench" \
  -v "${SPEC_DIR}:/workspace/cpu2017" \
  -v "${RESULTS_ROOT}:/workspace/results" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${OFFLINE_CONTAINER} created."
log "Mounted iBench: ${IBENCH_DIR} -> /workspace/iBench"
log "Mounted SPEC CPU: ${SPEC_DIR} -> /workspace/cpu2017"
log "Mounted results: ${RESULTS_ROOT} -> /workspace/results"
