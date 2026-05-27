#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"

require_cmd docker

log "Removing old ${LOADGEN_CONTAINER} if exists..."
docker rm -f "${LOADGEN_CONTAINER}" 2>/dev/null || true

volume_args=(-v "${RESULTS_ROOT}:/workspace/results")
if [[ "${DCPERF_MOUNT:-1}" == "1" ]]; then
  volume_args=(-v "${DCPERF_DIR}:/workspace/DCPerf" "${volume_args[@]}")
  log "Using host-mounted DCPerf: ${DCPERF_DIR} -> /workspace/DCPerf"
else
  log "Using image-baked DCPerf at /workspace/DCPerf"
fi

log "Creating ${LOADGEN_CONTAINER}..."
docker run -d --init --name "${LOADGEN_CONTAINER}" \
  --network host \
  --privileged \
  --cpuset-cpus="${LOADGEN_CPUSET}" \
  --cpuset-mems="${LOADGEN_MEMS}" \
  "${volume_args[@]}" \
  "${CLAB_IMAGE}" \
  sleep infinity

log "${LOADGEN_CONTAINER} created."
