#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

SERVER_LOG="${1:-/workspace/results/taobench_server.log}"
WARMUP_TIME="${2:-2400}"
TEST_TIME="${3:-7200}"
DCPERF_CODE_DIR="${DCPERF_CODE_DIR:-/workspace/DCPerf}"
STATE_DIR="${4:-${DCPERF_STATE_DIR:-}}"

if [[ -z "${STATE_DIR}" ]]; then
  if [[ "${SERVER_LOG}" == */logs/* ]]; then
    RUN_ROOT="${SERVER_LOG%/logs/*}"
    STATE_DIR="${RUN_ROOT}/dcperf_state/server"
  else
    STATE_DIR="/workspace/results/dcperf_state/server_$(date '+%Y%m%d_%H%M%S')"
  fi
fi

log "Starting TaoBench server in ${SERVER_CONTAINER}..."
log "server warmup_time=${WARMUP_TIME}, test_time=${TEST_TIME}"
log "server dcperf_code_dir=${DCPERF_CODE_DIR}, state_dir=${STATE_DIR}"

docker exec -d "${SERVER_CONTAINER}" bash -c "
set -euo pipefail
mkdir -p '${STATE_DIR}' &&
cd '${STATE_DIR}' &&
ln -sfn '${DCPERF_CODE_DIR}/benchpress' benchpress &&
ln -sfn '${DCPERF_CODE_DIR}/benchpress_cli.py' benchpress_cli.py &&
ln -sfn '${DCPERF_CODE_DIR}/packages' packages &&
ln -sfn '${DCPERF_CODE_DIR}/benchmarks' benchmarks &&
cp -f '${DCPERF_CODE_DIR}/benchmark_installs.txt' benchmark_installs.txt &&
ulimit -n ${ULIMIT_NOFILE} &&
nohup ./benchpress_cli.py run tao_bench_autoscale \
  -i '{\"num_servers\":1,\"memsize\":${TAO_MEMSIZE},\"interface_name\":\"${TAO_INTERFACE_NAME}\",\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME}}' \
  > ${SERVER_LOG} 2>&1 &
"

log "TaoBench server start command issued."
