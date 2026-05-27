#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

log "Removing old ${SERVER_CONTAINER} if exists..."
docker rm -f "${SERVER_CONTAINER}" 2>/dev/null || true

volume_args=(-v "${RESULTS_ROOT}:/workspace/results")
if [[ "${DCPERF_MOUNT:-1}" == "1" ]]; then
  volume_args=(-v "${DCPERF_DIR}:/workspace/DCPerf" "${volume_args[@]}")
  log "Using host-mounted DCPerf: ${DCPERF_DIR} -> /workspace/DCPerf"
else
  log "Using image-baked DCPerf at /workspace/DCPerf"
fi

log "Creating ${SERVER_CONTAINER}..."
docker run -d --init --name "${SERVER_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${SERVER_CPUSET}" \
  --cpuset-mems="${SERVER_MEMS}" \
  "${volume_args[@]}" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${SERVER_CONTAINER} created."
