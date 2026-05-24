#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# TaoBench Stage 1 matrix:
#   - Start TaoBench server once
#   - Full prewarm once
#   - Between conditions, use short recovery prewarm
#   - Run baseline checkpoints
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${CBS_ROOT}/conf/env.sh"
source "${CBS_ROOT}/scripts/common.sh"
source "${CBS_ROOT}/scripts/cleanup.sh"

# ----------------------------
# Global experiment parameters
# ----------------------------

EXP_NAME="${EXP_NAME:-stage1_recovery_matrix}"

CLIENTS="${CLIENTS_PER_THREAD:-900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-300}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

RECOVERY_PREWARM_ROUNDS="${RECOVERY_PREWARM_ROUNDS:-1}"
RECOVERY_PREWARM_TEST_TIME="${RECOVERY_PREWARM_TEST_TIME:-60}"

MEASURE_REPEATS="${MEASURE_REPEATS:-3}"
MEASURE_GAP="${MEASURE_GAP:-20}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-60}"
OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-30}"

TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-7200}"

SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"

ENABLE_SUDO="${ENABLE_SUDO:-1}"

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RESULTS_ROOT}/${EXP_NAME}_${RUN_TAG}"

mkdir -p "${RUN_DIR}/logs"
mkdir -p "${RUN_DIR}/raw"
mkdir -p "${RUN_DIR}/parsed"
mkdir -p "${RUN_DIR}/machine_topology"

SUMMARY="${RUN_DIR}/summary.csv"
PREWARM_SUMMARY="${RUN_DIR}/prewarm.csv"

SUDO_KEEPALIVE_PID=""

# ----------------------------
# Helpers
# ----------------------------

log() {
  echo "[$(date '+%F %T')] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

cleanup_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
  fi
}

# cleanup_all() {
#   log "Cleaning up..."
#   cleanup_sudo_keepalive || true
#   cleanup_offline || true
#   cleanup_taobench || true
# }

on_exit() {
  local code=$?
  log "Exiting with code=${code}. Cleaning up..."
  cleanup_sudo_keepalive || true
  cleanup_offline || true
  cleanup_taobench || true
  exit "${code}"
}

on_interrupt() {
  log "Interrupted. Cleaning up and exiting..."

  # 避免 exit 130 再触发 EXIT trap 导致重复 cleanup
  trap - EXIT

  cleanup_sudo_keepalive || true
  cleanup_offline || true
  cleanup_taobench || true

  exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

parse_json_field() {
  local json_file="$1"
  local key="$2"

  python3 - "$json_file" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1], sys.argv[2]

try:
    with open(path) as f:
        d = json.load(f)
    v = d.get(key, "")
    print("" if v is None else v)
except Exception:
    print("")
PY
}

write_csv_headers() {
  cat > "${SUMMARY}" <<'EOF'
timestamp,exp_name,condition_id,repeat_id,offline_type,offline_param,offline_label,spec_size,spec_copies,clients_per_thread,client_test_time,client_warmup_time,prewarm_rounds,prewarm_clients,prewarm_test_time,recovery_prewarm_rounds,recovery_prewarm_test_time,server_cpuset,server_mems,loadgen_cpuset,loadgen_mems,offline_cpuset,offline_mems,qps,gets_p99_ms,client_log,client_json,offline_log,run_dir,notes
EOF

  cat > "${PREWARM_SUMMARY}" <<'EOF'
phase,condition_id,round,clients_per_thread,test_time,qps,gets_p99_ms,client_log,client_json
EOF
}

save_experiment_meta() {
  {
    echo "timestamp=$(date -Iseconds)"
    echo "hostname=$(hostname)"
    echo "EXP_NAME=${EXP_NAME}"
    echo "RUN_DIR=${RUN_DIR}"
    echo
    echo "CLIENTS_PER_THREAD=${CLIENTS}"
    echo "CLIENT_TEST_TIME=${CLIENT_TEST_TIME}"
    echo "CLIENT_WARMUP_TIME=${CLIENT_WARMUP_TIME}"
    echo
    echo "PREWARM_CLIENTS=${PREWARM_CLIENTS}"
    echo "PREWARM_ROUNDS=${PREWARM_ROUNDS}"
    echo "PREWARM_TEST_TIME=${PREWARM_TEST_TIME}"
    echo
    echo "RECOVERY_PREWARM_ROUNDS=${RECOVERY_PREWARM_ROUNDS}"
    echo "RECOVERY_PREWARM_TEST_TIME=${RECOVERY_PREWARM_TEST_TIME}"
    echo
    echo "MEASURE_REPEATS=${MEASURE_REPEATS}"
    echo "MEASURE_GAP=${MEASURE_GAP}"
    echo
    echo "SERVER_BOOTSTRAP_WAIT=${SERVER_BOOTSTRAP_WAIT}"
    echo "OFFLINE_STABILIZE_WAIT=${OFFLINE_STABILIZE_WAIT}"
    echo "OFFLINE_COOLDOWN_WAIT=${OFFLINE_COOLDOWN_WAIT}"
    echo
    echo "TAO_SERVER_WARMUP_TIME=${TAO_SERVER_WARMUP_TIME}"
    echo "TAO_SERVER_TEST_TIME=${TAO_SERVER_TEST_TIME}"
    echo
    echo "SPEC_CONFIG=${SPEC_CONFIG}"
    echo
    echo "SERVER_CONTAINER=${SERVER_CONTAINER:-}"
    echo "LOADGEN_CONTAINER=${LOADGEN_CONTAINER:-}"
    echo "OFFLINE_CONTAINER=${OFFLINE_CONTAINER:-}"
    echo
    echo "SERVER_CPUSET=${SERVER_CPUSET:-}"
    echo "SERVER_MEMS=${SERVER_MEMS:-}"
    echo "LOADGEN_CPUSET=${LOADGEN_CPUSET:-}"
    echo "LOADGEN_MEMS=${LOADGEN_MEMS:-}"
    echo "OFFLINE_CPUSET=${OFFLINE_CPUSET:-}"
    echo "OFFLINE_MEMS=${OFFLINE_MEMS:-}"
    echo
    echo "TAO_MEMSIZE=${TAO_MEMSIZE:-}"
    echo "TAO_SERVER_PORT=${TAO_SERVER_PORT:-}"
    echo "TAO_INTERFACE_NAME=${TAO_INTERFACE_NAME:-}"
  } > "${RUN_DIR}/experiment_meta.env"
}

save_machine_topology_before() {
  log "Saving machine topology..."

  lscpu > "${RUN_DIR}/machine_topology/lscpu.txt" 2>&1 || true
  lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE > "${RUN_DIR}/machine_topology/lscpu_e.txt" 2>&1 || true
  numactl -H > "${RUN_DIR}/machine_topology/numactl_H.txt" 2>&1 || true
  cat /proc/cpuinfo > "${RUN_DIR}/machine_topology/proc_cpuinfo.txt" 2>&1 || true
  cat /proc/meminfo > "${RUN_DIR}/machine_topology/proc_meminfo_before.txt" 2>&1 || true
  cat /proc/interrupts > "${RUN_DIR}/machine_topology/proc_interrupts_before.txt" 2>&1 || true
  cat /proc/softirqs > "${RUN_DIR}/machine_topology/proc_softirqs_before.txt" 2>&1 || true

  if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-info > "${RUN_DIR}/machine_topology/cpupower_frequency_info.txt" 2>&1 || true
  fi
}

save_machine_topology_after() {
  cat /proc/meminfo > "${RUN_DIR}/machine_topology/proc_meminfo_after.txt" 2>&1 || true
  cat /proc/interrupts > "${RUN_DIR}/machine_topology/proc_interrupts_after.txt" 2>&1 || true
  cat /proc/softirqs > "${RUN_DIR}/machine_topology/proc_softirqs_after.txt" 2>&1 || true
}

start_sudo_keepalive() {
  if [[ "${ENABLE_SUDO}" != "1" ]]; then
    log "ENABLE_SUDO=0, skipping sudo keepalive."
    return 0
  fi

  sudo -v

  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &

  SUDO_KEEPALIVE_PID="$!"
}

apply_network_sysctl() {
  if [[ "${ENABLE_SUDO}" != "1" ]]; then
    log "ENABLE_SUDO=0, skipping network sysctl."
    return 0
  fi

  log "Applying network sysctl..."
  sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
  sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 || true
  sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 || true
}

create_containers() {
  log "Creating TaoBench server container..."
  bash "${CBS_ROOT}/containers/create_taobench_server.sh"

  log "Creating TaoBench loadgen container..."
  bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"

  log "Creating offline container..."
  bash "${CBS_ROOT}/containers/create_offline.sh"

  docker inspect "${SERVER_CONTAINER}" > "${RUN_DIR}/machine_topology/server_container.inspect.json" 2>/dev/null || true
  docker inspect "${LOADGEN_CONTAINER}" > "${RUN_DIR}/machine_topology/loadgen_container.inspect.json" 2>/dev/null || true
  docker inspect "${OFFLINE_CONTAINER}" > "${RUN_DIR}/machine_topology/offline_container.inspect.json" 2>/dev/null || true
}

start_taobench_server() {
  local server_log="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"

  log "Starting TaoBench server..."
  bash "${CBS_ROOT}/online/taobench/start_server.sh" \
    "${server_log}" \
    "${TAO_SERVER_WARMUP_TIME}" \
    "${TAO_SERVER_TEST_TIME}"

  log "Waiting for TaoBench server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
  sleep "${SERVER_BOOTSTRAP_WAIT}"
}

run_client_once() {
  local phase="$1"
  local condition_id="$2"
  local round_or_repeat="$3"
  local clients="$4"
  local test_time="$5"
  local log_file="$6"
  local json_file="$7"

  log "Running TaoBench client: phase=${phase}, condition=${condition_id}, id=${round_or_repeat}, clients=${clients}, test_time=${test_time}"

  bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${clients}" \
    "${test_time}" \
    "${log_file}" 

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" \
    "${log_file}" \
    --json-out "${json_file}" || true
}

full_prewarm() {
  log "Starting full prewarm: rounds=${PREWARM_ROUNDS}, clients=${PREWARM_CLIENTS}, test_time=${PREWARM_TEST_TIME}"

  for round in $(seq 1 "${PREWARM_ROUNDS}"); do
    local client_log="${RUN_DIR}/raw/full_prewarm_round_${round}.log"
    local client_json="${RUN_DIR}/parsed/full_prewarm_round_${round}.json"

    run_client_once \
      "full_prewarm" \
      "initial" \
      "${round}" \
      "${PREWARM_CLIENTS}" \
      "${PREWARM_TEST_TIME}" \
      "${client_log}" \
      "${client_json}"

    local qps
    local p99
    qps="$(parse_json_field "${client_json}" qps)"
    p99="$(parse_json_field "${client_json}" gets_p99_ms)"

    echo "full_prewarm,initial,${round},${PREWARM_CLIENTS},${PREWARM_TEST_TIME},${qps},${p99},${client_log},${client_json}" >> "${PREWARM_SUMMARY}"

    log "Full prewarm round ${round}/${PREWARM_ROUNDS}: qps=${qps}, p99=${p99}"

    sleep 10
  done
}

recovery_prewarm() {
  local condition_id="$1"

  if [[ "${RECOVERY_PREWARM_ROUNDS}" -le 0 ]]; then
    log "RECOVERY_PREWARM_ROUNDS=${RECOVERY_PREWARM_ROUNDS}, skipping recovery prewarm."
    return 0
  fi

  log "Starting recovery prewarm before ${condition_id}: rounds=${RECOVERY_PREWARM_ROUNDS}, test_time=${RECOVERY_PREWARM_TEST_TIME}"

  for round in $(seq 1 "${RECOVERY_PREWARM_ROUNDS}"); do
    local client_log="${RUN_DIR}/raw/recovery_before_${condition_id}_round_${round}.log"
    local client_json="${RUN_DIR}/parsed/recovery_before_${condition_id}_round_${round}.json"

    run_client_once \
      "recovery_prewarm" \
      "${condition_id}" \
      "${round}" \
      "${PREWARM_CLIENTS}" \
      "${RECOVERY_PREWARM_TEST_TIME}" \
      "${client_log}" \
      "${client_json}"

    local qps
    local p99
    qps="$(parse_json_field "${client_json}" qps)"
    p99="$(parse_json_field "${client_json}" gets_p99_ms)"

    echo "recovery_prewarm,${condition_id},${round},${PREWARM_CLIENTS},${RECOVERY_PREWARM_TEST_TIME},${qps},${p99},${client_log},${client_json}" >> "${PREWARM_SUMMARY}"

    log "Recovery prewarm before ${condition_id}, round ${round}/${RECOVERY_PREWARM_ROUNDS}: qps=${qps}, p99=${p99}"

    sleep 5
  done
}

start_offline() {
  local offline_type="$1"
  local offline_param="$2"
  local offline_label="$3"
  local spec_size="$4"
  local spec_copies="$5"
  local offline_log="$6"

  case "${offline_type}" in
    none)
      log "No offline workload for this condition."
      ;;

    ibench_cpu)
      [[ -n "${offline_param}" ]] || die "ibench_cpu requires offline_param"
      log "Starting ibench_cpu: param=${offline_param}"
      bash "${CBS_ROOT}/offline/ibench/start_cpu.sh" \
        "${offline_param}" \
        "${offline_log}"
      ;;

    ibench_membw)
      [[ -n "${offline_param}" ]] || die "ibench_membw requires offline_param"
      log "Starting ibench_membw: param=${offline_param}"
      bash "${CBS_ROOT}/offline/ibench/start_membw.sh" \
        "${offline_param}" \
        "${offline_log}"
      ;;

    ibench_l3)
      [[ -n "${offline_param}" ]] || die "ibench_l3 requires offline_param"
      log "Starting ibench_l3: param=${offline_param}"
      bash "${CBS_ROOT}/offline/ibench/start_l3.sh" \
        "${offline_param}" \
        "${offline_log}"
      ;;

    ibench_memcap)
      die "ibench_memcap is disabled for Stage 1 because it may cause OOM-like behavior."
      ;;

    spec_mcf)
      [[ -n "${spec_size}" ]] || die "spec_mcf requires spec_size"
      [[ -n "${spec_copies}" ]] || die "spec_mcf requires spec_copies"
      log "Starting spec_mcf: size=${spec_size}, copies=${spec_copies}, config=${SPEC_CONFIG}"
      SPEC_COPIES="${spec_copies}" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" \
        "505.mcf_r" \
        "${offline_log}" \
        "${spec_size}" \
        "${SPEC_CONFIG}"
      ;;

    spec_lbm)
      [[ -n "${spec_size}" ]] || die "spec_lbm requires spec_size"
      [[ -n "${spec_copies}" ]] || die "spec_lbm requires spec_copies"
      log "Starting spec_lbm: size=${spec_size}, copies=${spec_copies}, config=${SPEC_CONFIG}"
      SPEC_COPIES="${spec_copies}" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" \
        "519.lbm_r" \
        "${offline_log}" \
        "${spec_size}" \
        "${SPEC_CONFIG}"
      ;;

    *)
      die "Unknown offline_type=${offline_type}"
      ;;
  esac

  if [[ "${offline_type}" != "none" ]]; then
    log "Waiting for offline workload to stabilize: ${OFFLINE_STABILIZE_WAIT}s"
    sleep "${OFFLINE_STABILIZE_WAIT}"
  fi
}

run_measured_repeats() {
  local condition_id="$1"
  local offline_type="$2"
  local offline_param="$3"
  local offline_label="$4"
  local spec_size="$5"
  local spec_copies="$6"
  local offline_log="$7"

  for repeat_id in $(seq 1 "${MEASURE_REPEATS}"); do
    local client_log="${RUN_DIR}/raw/${condition_id}_repeat_${repeat_id}.log"
    local client_json="${RUN_DIR}/parsed/${condition_id}_repeat_${repeat_id}.json"

    run_client_once \
      "measured" \
      "${condition_id}" \
      "${repeat_id}" \
      "${CLIENTS}" \
      "${CLIENT_TEST_TIME}" \
      "${client_log}" \
      "${client_json}"

    local qps
    local p99
    qps="$(parse_json_field "${client_json}" qps)"
    p99="$(parse_json_field "${client_json}" gets_p99_ms)"

    echo "$(date -Iseconds),${EXP_NAME},${condition_id},${repeat_id},${offline_type},${offline_param},${offline_label},${spec_size},${spec_copies},${CLIENTS},${CLIENT_TEST_TIME},${CLIENT_WARMUP_TIME},${PREWARM_ROUNDS},${PREWARM_CLIENTS},${PREWARM_TEST_TIME},${RECOVERY_PREWARM_ROUNDS},${RECOVERY_PREWARM_TEST_TIME},${SERVER_CPUSET:-},${SERVER_MEMS:-},${LOADGEN_CPUSET:-},${LOADGEN_MEMS:-},${OFFLINE_CPUSET:-},${OFFLINE_MEMS:-},${qps},${p99},${client_log},${client_json},${offline_log},${RUN_DIR}," >> "${SUMMARY}"

    log "Measured result: condition=${condition_id}, repeat=${repeat_id}/${MEASURE_REPEATS}, qps=${qps}, p99=${p99}"

    if [[ "${repeat_id}" != "${MEASURE_REPEATS}" ]]; then
      log "Sleeping between measured repeats: ${MEASURE_GAP}s"
      sleep "${MEASURE_GAP}"
    fi
  done
}

recreate_offline_container() {
  local condition_id="${1:-unknown}"

  log "Recreating offline container for condition=${condition_id}..."

  # cleanup_offline 会删除 clab-offline，所以删完必须重建
  cleanup_offline || true

  bash "${CBS_ROOT}/containers/create_offline.sh"

  docker inspect "${OFFLINE_CONTAINER}" \
    > "${RUN_DIR}/machine_topology/offline_container_${condition_id}.inspect.json" \
    2>/dev/null || true
}

run_condition() {
  local condition_id="$1"
  local offline_type="$2"
  local offline_param="$3"
  local offline_label="$4"
  local spec_size="${5:-}"
  local spec_copies="${6:-}"

  local offline_log="${RUN_DIR}/logs/offline_${condition_id}.log"

  log "============================================================"
  log "Condition: ${condition_id}"
  log "offline_type=${offline_type}"
  log "offline_param=${offline_param}"
  log "offline_label=${offline_label}"
  log "spec_size=${spec_size}"
  log "spec_copies=${spec_copies}"
  log "============================================================"

  # 每个 condition 开始前，保证 offline container 存在且是干净的
  recreate_offline_container "${condition_id}"

  # baseline_none 紧跟完整 8 轮 prewarm，不需要 recovery prewarm
  if [[ "${condition_id}" != "baseline_none" ]]; then
    log "Cooldown before recovery prewarm: ${OFFLINE_COOLDOWN_WAIT}s"
    sleep "${OFFLINE_COOLDOWN_WAIT}"

    # 此时没有 offline workload，做一次 recovery prewarm
    recovery_prewarm "${condition_id}"
  else
    log "Skipping recovery prewarm for baseline_none because it follows full prewarm."
  fi

  # 启动当前 condition 的 offline workload
  start_offline \
    "${offline_type}" \
    "${offline_param}" \
    "${offline_label}" \
    "${spec_size}" \
    "${spec_copies}" \
    "${offline_log}"

  # 正式测量
  run_measured_repeats \
    "${condition_id}" \
    "${offline_type}" \
    "${offline_param}" \
    "${offline_label}" \
    "${spec_size}" \
    "${spec_copies}" \
    "${offline_log}"

  # 当前 condition 结束后，停止 offline workload
  # 注意：这会删除 clab-offline，所以后面 condition 会重新创建
  if [[ "${offline_type}" != "none" ]]; then
    log "Stopping offline workload after condition=${condition_id}"
    cleanup_offline || true
  fi
}

run_stage1_matrix() {
  # ------------------------------------------------------------
  # Baseline
  # ------------------------------------------------------------
  run_condition "baseline_none" "none" "" "none" "" ""

  # ------------------------------------------------------------
  # iBench CPU sanity
  # ------------------------------------------------------------
  run_condition "ibench_cpu_w8" "ibench_cpu" "8" "w8" "" ""

  # ------------------------------------------------------------
  # iBench memory bandwidth gradient
  # ------------------------------------------------------------
  run_condition "ibench_membw_w2" "ibench_membw" "2" "w2" "" ""
  run_condition "ibench_membw_w4" "ibench_membw" "4" "w4" "" ""
  run_condition "ibench_membw_w8" "ibench_membw" "8" "w8" "" ""

  # Baseline checkpoint after memory bandwidth workloads
  run_condition "baseline_after_membw" "none" "" "none" "" ""

  # ------------------------------------------------------------
  # iBench L3 / LLC gradient
  # ------------------------------------------------------------
  run_condition "ibench_l3_w2" "ibench_l3" "2" "w2" "" ""
  run_condition "ibench_l3_w4" "ibench_l3" "4" "w4" "" ""
  run_condition "ibench_l3_w8" "ibench_l3" "8" "w8" "" ""

  # Baseline checkpoint after L3 workloads
  run_condition "baseline_after_l3" "none" "" "none" "" ""

  # ------------------------------------------------------------
  # SPEC mcf gradient
  # ------------------------------------------------------------
  run_condition "spec_mcf_ref_c2" "spec_mcf" "" "ref_c2" "ref" "2"
  run_condition "spec_mcf_ref_c4" "spec_mcf" "" "ref_c4" "ref" "4"
  run_condition "spec_mcf_ref_c8" "spec_mcf" "" "ref_c8" "ref" "8"

  # Baseline checkpoint after mcf
  run_condition "baseline_after_mcf" "none" "" "none" "" ""

  # ------------------------------------------------------------
  # SPEC lbm gradient
  # ------------------------------------------------------------
  run_condition "spec_lbm_ref_c2" "spec_lbm" "" "ref_c2" "ref" "2"
  run_condition "spec_lbm_ref_c4" "spec_lbm" "" "ref_c4" "ref" "4"
  run_condition "spec_lbm_ref_c8" "spec_lbm" "" "ref_c8" "ref" "8"

  # Final baseline checkpoint
  run_condition "baseline_final" "none" "" "none" "" ""
}

# ----------------------------
# Main
# ----------------------------

log "Run directory: ${RUN_DIR}"

write_csv_headers
save_experiment_meta
save_machine_topology_before
start_sudo_keepalive
create_containers
apply_network_sysctl
start_taobench_server
full_prewarm

log "Full prewarm finished. Starting Stage 1 matrix with recovery prewarm between conditions."

run_stage1_matrix

save_machine_topology_after

log "All Stage 1 experiments finished."
log "Summary CSV: ${SUMMARY}"
log "Prewarm CSV: ${PREWARM_SUMMARY}"
log "Run directory: ${RUN_DIR}"