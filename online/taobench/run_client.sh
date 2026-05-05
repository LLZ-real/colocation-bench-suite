#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

CLIENTS_PER_THREAD="${1:?Usage: run_client.sh <clients_per_thread> <test_time> <out_log>}"
TEST_TIME="${2:-60}"
OUT_LOG="${3:?Usage: run_client.sh <clients_per_thread> <test_time> <out_log>}"

log "Running TaoBench client: clients_per_thread=${CLIENTS_PER_THREAD}, test_time=${TEST_TIME}"

docker exec "${LOADGEN_CONTAINER}" bash -c "
cd /workspace/DCPerf &&
ulimit -n ${ULIMIT_NOFILE} &&
./benchpress_cli.py run tao_bench_custom -r client \
  -i '{\"server_hostname\":\"127.0.0.1\",\"server_memsize\":${TAO_MEMSIZE}.0,\"warmup_time\":120,\"test_time\":${TEST_TIME},\"server_port_number\":${TAO_SERVER_PORT},\"wait_after_warmup\":5,\"clients_per_thread\":${CLIENTS_PER_THREAD}}'
" > "${OUT_LOG}" 2>&1

log "Client run done. Log: ${OUT_LOG}"
