#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

log "Removing old ${OFFLINE_CONTAINER} if exists..."
docker rm -f "${OFFLINE_CONTAINER}" 2>/dev/null || true

log "Creating ${OFFLINE_CONTAINER}..."
docker run -d --name "${OFFLINE_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${OFFLINE_CPUSET}" \
  --cpuset-mems="${OFFLINE_MEMS}" \
  -v "${IBENCH_DIR}:/workspace/iBench" \
  -v "${RESULTS_ROOT}:/workspace/results" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${OFFLINE_CONTAINER} created."
