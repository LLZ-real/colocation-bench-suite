#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

NUM_WORKERS="${1:-8}"
OUT_LOG="${2:-/workspace/results/ibench_membw.log}"
IBENCH_MEMBW_ARG="${IBENCH_MEMBW_ARG:-30}"

log "Starting iBench memBw interference: workers=${NUM_WORKERS}, ibench_arg=${IBENCH_MEMBW_ARG}"

docker exec -d "${OFFLINE_CONTAINER}" bash -c "
set -e
cd /workspace/iBench
mkdir -p \$(dirname '${OUT_LOG}')

echo '[ibench memBw] workers=${NUM_WORKERS}, ibench_arg=${IBENCH_MEMBW_ARG}' > '${OUT_LOG}'
echo '[ibench memBw] start_time='\"\$(date '+%F %T')\" >> '${OUT_LOG}'

if [ ! -x ./src/memBw ]; then
  echo '[ERROR] ./src/memBw not found or not executable' >> '${OUT_LOG}'
  exit 1
fi

for i in \$(seq 1 ${NUM_WORKERS}); do
  nohup bash -c '
    while true; do
      /workspace/iBench/src/memBw ${IBENCH_MEMBW_ARG}
    done
  ' >> '${OUT_LOG}' 2>&1 &
  echo \$! > /tmp/ibench_membw_worker_\${i}.pid
done

echo '[ibench memBw] started workers:' >> '${OUT_LOG}'
for f in /tmp/ibench_membw_worker_*.pid; do
  echo \"\$f \$(cat \$f)\" >> '${OUT_LOG}'
done

pgrep -af '/workspace/iBench/src/memBw|ibench_membw_worker|while true' >> '${OUT_LOG}' || true
"
