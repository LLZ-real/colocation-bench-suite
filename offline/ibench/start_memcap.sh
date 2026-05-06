#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

SIZE_GB="${1:-15}"
OUT_LOG="${2:-/workspace/results/ibench_memcap.log}"

log "Starting iBench memCap interference: size_gb=${SIZE_GB}"

docker exec -d "${OFFLINE_CONTAINER}" bash -c "
cd /workspace/iBench &&
mkdir -p \$(dirname '${OUT_LOG}') &&
if [ -x ./src/memCap ]; then
  nohup ./src/memCap ${SIZE_GB} > '${OUT_LOG}' 2>&1 &
elif [ -x ./memCap ]; then
  nohup ./memCap ${SIZE_GB} > '${OUT_LOG}' 2>&1 &
else
  echo 'Cannot find memCap binary' > '${OUT_LOG}'
  exit 1
fi
"

log "iBench memCap started."
