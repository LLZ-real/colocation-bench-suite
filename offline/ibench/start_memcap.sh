#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

SIZE_GB="${1:-4}"
OUT_LOG="${2:-/workspace/results/ibench_memcap.log}"

log "Starting iBench memCap interference: size_gb=${SIZE_GB}"

docker exec -d "${OFFLINE_CONTAINER}" bash -c "
set -e
cd /workspace/iBench
mkdir -p \$(dirname '${OUT_LOG}')

echo '[ibench memCap] size_gb=${SIZE_GB}' > '${OUT_LOG}'
echo '[ibench memCap] start_time='\"\$(date '+%F %T')\" >> '${OUT_LOG}'

if [ -x ./src/memCap ]; then
  BIN=/workspace/iBench/src/memCap
elif [ -x ./memCap ]; then
  BIN=/workspace/iBench/memCap
else
  echo '[ERROR] memCap binary not found' >> '${OUT_LOG}'
  exit 1
fi

nohup \${BIN} ${SIZE_GB} >> '${OUT_LOG}' 2>&1 &
echo \$! > /tmp/ibench_memcap.pid

echo '[ibench memCap] pid:' >> '${OUT_LOG}'
cat /tmp/ibench_memcap.pid >> '${OUT_LOG}'
pgrep -af 'memCap' >> '${OUT_LOG}' || true
"
