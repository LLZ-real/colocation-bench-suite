#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

NUM_WORKERS="${1:-8}"
OUT_LOG="${2:-/workspace/results/ibench_l3.log}"
IBENCH_L3_ARG="${IBENCH_L3_ARG:-30}"

log "Starting iBench L3 interference: workers=${NUM_WORKERS}, ibench_arg=${IBENCH_L3_ARG}"

docker exec -d "${OFFLINE_CONTAINER}" bash -c "
set -e
cd /workspace/iBench
mkdir -p \$(dirname '${OUT_LOG}')

echo '[ibench l3] workers=${NUM_WORKERS}, ibench_arg=${IBENCH_L3_ARG}' > '${OUT_LOG}'
echo '[ibench l3] start_time='\"\$(date '+%F %T')\" >> '${OUT_LOG}'

if [ ! -x ./src/l3 ]; then
  echo '[ERROR] ./src/l3 not found or not executable' >> '${OUT_LOG}'
  exit 1
fi

for i in \$(seq 1 ${NUM_WORKERS}); do
  nohup bash -c '
    while true; do
      /workspace/iBench/src/l3 ${IBENCH_L3_ARG}
    done
  ' >> '${OUT_LOG}' 2>&1 &
  echo \$! > /tmp/ibench_l3_worker_\${i}.pid
done

echo '[ibench l3] started workers:' >> '${OUT_LOG}'
for f in /tmp/ibench_l3_worker_*.pid; do
  echo \"\$f \$(cat \$f)\" >> '${OUT_LOG}'
done

pgrep -af '/workspace/iBench/src/l3|ibench_l3_worker|while true' >> '${OUT_LOG}' || true
"
