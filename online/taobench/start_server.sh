#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"
source "$(dirname "$0")/../../scripts/common.sh"

SERVER_LOG="${1:-/workspace/results/taobench_server.log}"
WARMUP_TIME="${2:-120}"
TEST_TIME="${3:-7200}"

log "Starting TaoBench server in ${SERVER_CONTAINER}..."

docker exec -d "${SERVER_CONTAINER}" bash -c "
cd /workspace/DCPerf &&
ulimit -n ${ULIMIT_NOFILE} &&
nohup ./benchpress_cli.py run tao_bench_autoscale \
  -i '{\"num_servers\":1,\"memsize\":${TAO_MEMSIZE},\"interface_name\":\"${TAO_INTERFACE_NAME}\",\"warmup_time\":${WARMUP_TIME},\"test_time\":${TEST_TIME}}' \
  > ${SERVER_LOG} 2>&1 &
"

log "TaoBench server start command issued."
