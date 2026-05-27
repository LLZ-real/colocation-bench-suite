#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

CLIENTS_PER_THREAD="${1:?Usage: run_client.sh <clients_per_thread> <test_time> <out_log>}"
TEST_TIME="${2:-60}"
OUT_LOG="${3:?Usage: run_client.sh <clients_per_thread> <test_time> <out_log>}"
WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"
DCPERF_CODE_DIR="${DCPERF_CODE_DIR:-/workspace/DCPerf}"
STATE_DIR="${4:-${DCPERF_STATE_DIR:-}}"

if [[ -z "${STATE_DIR}" ]]; then
  STATE_DIR="/workspace/results/dcperf_state/loadgen_$(date '+%Y%m%d_%H%M%S')"
fi

log "Running TaoBench client: clients_per_thread=${CLIENTS_PER_THREAD}, warmup_time=${WARMUP_TIME}, test_time=${TEST_TIME}"
log "client dcperf_code_dir=${DCPERF_CODE_DIR}, state_dir=${STATE_DIR}"

docker exec "${LOADGEN_CONTAINER}" bash -c "
set -euo pipefail
mkdir -p '${STATE_DIR}' &&
cd '${STATE_DIR}' &&
ln -sfn '${DCPERF_CODE_DIR}/benchpress' benchpress &&
ln -sfn '${DCPERF_CODE_DIR}/benchpress_cli.py' benchpress_cli.py &&
ln -sfn '${DCPERF_CODE_DIR}/packages' packages &&
ln -sfn '${DCPERF_CODE_DIR}/benchmarks' benchmarks &&
cp -f '${DCPERF_CODE_DIR}/benchmark_installs.txt' benchmark_installs.txt &&
ulimit -n ${ULIMIT_NOFILE} &&
./benchpress_cli.py run tao_bench_custom -r client \
  -i '{\"server_hostname\":\"127.0.0.1\",\"server_memsize\":${TAO_MEMSIZE}.0,\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME},\"server_port_number\":${TAO_SERVER_PORT},\"wait_after_warmup\":5,\"clients_per_thread\":${CLIENTS_PER_THREAD}}'
" > "${OUT_LOG}" 2>&1

log "Client run done. Log: ${OUT_LOG}"
