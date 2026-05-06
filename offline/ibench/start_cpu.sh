#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

NUM_WORKERS="${1:-8}"
OUT_LOG="${2:-/workspace/results/ibench_cpu.log}"
IBENCH_CPU_ARG="${IBENCH_CPU_ARG:-30}"

log "Starting iBench CPU interference: workers=${NUM_WORKERS}, ibench_arg=${IBENCH_CPU_ARG}"

docker exec -d "${OFFLINE_CONTAINER}" bash -c "
set -e
cd /workspace/iBench
mkdir -p \$(dirname '${OUT_LOG}')

echo '[ibench cpu] workers=${NUM_WORKERS}, ibench_arg=${IBENCH_CPU_ARG}' > '${OUT_LOG}'
echo '[ibench cpu] start_time='\"\$(date '+%F %T')\" >> '${OUT_LOG}'

if [ ! -x ./src/cpu ]; then
  echo '[ERROR] ./src/cpu not found or not executable' >> '${OUT_LOG}'
  exit 1
fi

for i in \$(seq 1 ${NUM_WORKERS}); do
  nohup bash -c '
    while true; do
      /workspace/iBench/src/cpu ${IBENCH_CPU_ARG}
    done
  ' >> '${OUT_LOG}' 2>&1 &
  echo \$! > /tmp/ibench_cpu_worker_\${i}.pid
done

echo '[ibench cpu] started workers:' >> '${OUT_LOG}'
for f in /tmp/ibench_cpu_worker_*.pid; do
  echo \"\$f \$(cat \$f)\" >> '${OUT_LOG}'
done

pgrep -af '/workspace/iBench/src/cpu|ibench_cpu_worker|while true' >> '${OUT_LOG}' || true
"
