#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../conf/env.sh"
source "$(dirname "$0")/../scripts/common.sh"
source "$(dirname "$0")/../scripts/cleanup.sh"

trap cleanup_taobench EXIT INT TERM

EXP_NAME="taobench_baseline_curve"
make_run_dir "${EXP_NAME}"

save_machine_topology "${RUN_DIR}/machine_topology"
write_config_snapshot "${RUN_DIR}/config.env"

log "Creating containers..."
bash "${CBS_ROOT}/containers/create_taobench_server.sh"
bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"

log "Applying network sysctl..."
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
sudo sysctl -w net.ipv4.tcp_tw_reuse=1 || true
sudo sysctl -w net.ipv4.tcp_fin_timeout=15 || true

log "Starting TaoBench server..."
SERVER_LOG="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
mkdir -p "${RUN_DIR}/logs"
bash "${CBS_ROOT}/online/taobench/start_server.sh" "${SERVER_LOG}" 120 7200

log "Waiting for server warmup bootstrap..."
sleep 180

SUMMARY="${RUN_DIR}/summary.csv"
echo "clients_per_thread,qps,gets_p99_ms,log_file" > "${SUMMARY}"

CLIENT_LIST="${CLIENT_LIST:-100 200 300 380 500 600 700 800 900 1000 1200 1400}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"

for CLIENTS in ${CLIENT_LIST}; do
  log "Testing clients_per_thread=${CLIENTS}"

  LOG_FILE="${RUN_DIR}/raw/client_${CLIENTS}.log"
  JSON_FILE="${RUN_DIR}/parsed/client_${CLIENTS}.json"

  bash "${CBS_ROOT}/online/taobench/run_client.sh" "${CLIENTS}" "${CLIENT_TEST_TIME}" "${LOG_FILE}" || true

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" "${LOG_FILE}" --json-out "${JSON_FILE}"

  QPS="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('qps') if d.get('qps') is not None else '')")"
  P99="$(python3 -c "import json; d=json.load(open('${JSON_FILE}')); print(d.get('gets_p99_ms') if d.get('gets_p99_ms') is not None else '')")"

  echo "${CLIENTS},${QPS},${P99},${LOG_FILE}" >> "${SUMMARY}"

  log "Result: clients=${CLIENTS}, qps=${QPS}, gets_p99_ms=${P99}"

  if [ -n "${P99}" ]; then
    EXCEEDED="$(echo "${P99} > 500" | bc -l || echo 0)"
    if [ "${EXCEEDED}" = "1" ]; then
      log "P99 exceeded 500ms. Stop curve scan."
      break
    fi
  fi

  sleep 15
done

log "Baseline curve finished."
log "Summary: ${SUMMARY}"
