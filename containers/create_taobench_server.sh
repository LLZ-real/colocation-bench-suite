#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

log "Removing old ${SERVER_CONTAINER} if exists..."
docker rm -f "${SERVER_CONTAINER}" 2>/dev/null || true

log "Creating ${SERVER_CONTAINER}..."
docker run -d --init --name "${SERVER_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${SERVER_CPUSET}" \
  --cpuset-mems="${SERVER_MEMS}" \
  -v "${DCPERF_DIR}:/workspace/DCPerf" \
  -v "${RESULTS_ROOT}:/workspace/results" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${SERVER_CONTAINER} created."
