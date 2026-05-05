#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

log "Removing old ${LOADGEN_CONTAINER} if exists..."
docker rm -f "${LOADGEN_CONTAINER}" 2>/dev/null || true

log "Creating ${LOADGEN_CONTAINER}..."
docker run -d --name "${LOADGEN_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${LOADGEN_CPUSET}" \
  --cpuset-mems="${LOADGEN_MEMS}" \
  -v "${DCPERF_DIR}:/workspace/DCPerf" \
  -v "${RESULTS_ROOT}:/workspace/results" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${LOADGEN_CONTAINER} created."
