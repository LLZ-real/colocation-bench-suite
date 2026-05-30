#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Stage 1-A: Clean performance data sweep (no perf).
#
# Usage:
#   PLACEMENT=same_numa \
#   MATRIX_FILE=docs/stage1_ibench_matrix.csv \
#   EXP_NAME=stage1_same_numa_clean \
#   bash experiments/data_collection_experiment/stage1_sweep_clean.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${CBS_ROOT}/conf/env.sh"
source "${CBS_ROOT}/scripts/common.sh"
source "${CBS_ROOT}/scripts/cleanup.sh"

# ----------------------------
# User-configurable parameters
# ----------------------------

PLACEMENT="${PLACEMENT:?set PLACEMENT to same_numa, cross_numa, or same_smt}"
MATRIX_FILE="${MATRIX_FILE:?set MATRIX_FILE to the condition CSV path}"
EXP_NAME="${EXP_NAME:-stage1_${PLACEMENT}_clean}"

CLIENTS="${CLIENTS_PER_THREAD:-900}"
CLIENT_TEST_TIME="${CLIENT_TEST_TIME:-60}"
CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME:-120}"

PREWARM_CLIENTS="${PREWARM_CLIENTS:-900}"
PREWARM_ROUNDS="${PREWARM_ROUNDS:-8}"
PREWARM_TEST_TIME="${PREWARM_TEST_TIME:-60}"

MEASURE_REPEATS="${MEASURE_REPEATS:-1}"
MEASURE_GAP="${MEASURE_GAP:-5}"

SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT:-180}"
OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT:-30}"
OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT:-5}"

# Server test time: default 14400 (4h). For large matrices, increase this.
TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME:-2400}"
TAO_SERVER_TEST_TIME="${TAO_SERVER_TEST_TIME:-14400}"

BASELINE_INTERVAL="${BASELINE_INTERVAL:-10}"

SPEC_CONFIG="${SPEC_CONFIG:-my_test.cfg}"
ENABLE_SUDO="${ENABLE_SUDO:-1}"

# ----------------------------
# Placement → cpuset mapping
# ----------------------------

# NOTE: use direct assignment below (not ${VAR:-default}) because conf/env.sh
# already set OFFLINE_CPUSET/MEMS via its own ${VAR:-default}. The case
# statement must FORCE the correct placement value.
case "${PLACEMENT}" in
  same_numa)
    OFFLINE_CPUSET="16,17,18,19,20,21,22,23"
    OFFLINE_MEMS="0"
    ;;
  cross_numa)
    OFFLINE_CPUSET="48,49,50,51,52,53,54,55"
    OFFLINE_MEMS="1"
    ;;
  same_smt)
    OFFLINE_CPUSET="64,65,66,67,68,69,70,71"
    OFFLINE_MEMS="0"
    ;;
  *)
    die "Unknown PLACEMENT=${PLACEMENT}. Must be same_numa, cross_numa, or same_smt"
    ;;
esac

# ----------------------------
# Run directory
# ----------------------------

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RESULTS_ROOT}/${EXP_NAME}_${RUN_TAG}"

mkdir -p "${RUN_DIR}/logs"
mkdir -p "${RUN_DIR}/raw"
mkdir -p "${RUN_DIR}/parsed"
mkdir -p "${RUN_DIR}/machine_topology"
mkdir -p "${RUN_DIR}/progress"

SUMMARY="${RUN_DIR}/summary.csv"
PROGRESS_FILE="${RUN_DIR}/progress/completed.csv"
FAILURES_FILE="${RUN_DIR}/progress/failures.csv"
PREFLIGHT_LOG="${RUN_DIR}/machine_topology/preflight.txt"

SUDO_KEEPALIVE_PID=""

# ----------------------------
# Helpers
# ----------------------------

log() {
  # Write to log file AND stderr. Do NOT write to stdout — stdout is used
  # by $(...) captures in run_measured_client_for_condition and would
  # pollute the pipe-delimited result strings.
  echo "[$(date '+%F %T')] $*" >> "${RUN_DIR}/progress/full.log"
  echo "[$(date '+%F %T')] $*" >&2
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

on_exit() {
  local code=$?
  log "Exiting with code=${code}. Cleaning up..."
  cleanup_sudo_keepalive || true
  cleanup_offline || true
  cleanup_taobench || true
  docker rm -f "${SERVER_CONTAINER}" "${LOADGEN_CONTAINER}" "${OFFLINE_CONTAINER}" 2>/dev/null || true
  exit "${code}"
}

on_interrupt() {
  log "Interrupted. Cleaning up and exiting..."
  trap - EXIT
  cleanup_sudo_keepalive || true
  cleanup_offline || true
  cleanup_taobench || true
  docker rm -f "${SERVER_CONTAINER}" "${LOADGEN_CONTAINER}" "${OFFLINE_CONTAINER}" 2>/dev/null || true
  exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

parse_json_field() {
  local json_file="$1"
  local key="$2"
  python3 - "$json_file" "$key" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2], "")
    print("" if v is None else v)
except Exception:
    print("")
PY
}

write_summary_header() {
  cat > "${SUMMARY}" <<'EOF'
timestamp,exp_name,placement,condition_id,repeat_id,offline_type,offline_param,offline_intensity,offline_label,spec_size,spec_copies,spec_bench,clients_per_thread,client_test_time,client_warmup_time,server_cpuset,server_mems,loadgen_cpuset,loadgen_mems,offline_cpuset,offline_mems,qps,gets_p99_ms,client_log,client_json,offline_log,run_dir,notes
EOF
}

csv_append_row() {
  python3 - "${SUMMARY}" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], "a", newline="") as f:
    csv.writer(f).writerow(sys.argv[2:])
PY
}

save_progress() {
  local condition_id="$1"
  echo "${condition_id}" >> "${PROGRESS_FILE}"
}

record_failure() {
  local condition_id="$1"
  local reason="${2:-unknown}"
  echo "${condition_id},${reason}" >> "${FAILURES_FILE}"
}

load_completed() {
  if [[ -f "${PROGRESS_FILE}" ]]; then
    sort -u "${PROGRESS_FILE}"
  fi
}

# ----------------------------
# System environment capture (preflight)
# ----------------------------

capture_system_state() {
  log "Capturing full system state..."

  {
    echo "=== PREFLIGHT @ $(date -Iseconds) ==="
    echo

    echo "=== SMT / Hyperthreading ==="
    if [[ -f /sys/devices/system/cpu/smt/active ]]; then
      echo "SMT active: $(cat /sys/devices/system/cpu/smt/active)"
    else
      echo "SMT active: unknown (file missing)"
    fi
    if [[ -f /sys/devices/system/cpu/smt/control ]]; then
      echo "SMT control: $(cat /sys/devices/system/cpu/smt/control)"
    fi
    echo

    echo "=== CPU frequency ==="
    if command -v cpupower &>/dev/null; then
      cpupower frequency-info 2>&1 || true
    else
      echo "cpupower not available"
      echo "scaling_governor (cpu0): $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
      echo "scaling_available_governors: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null || echo unknown)"
      for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        [[ -f "${cpu}" ]] && echo "$(basename "$(dirname "${cpu}")"): $(cat "${cpu}")"
      done
    fi
    echo

    echo "=== CPU idle states (C-states) ==="
    for f in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
      [[ -f "${f}" ]] || continue
      local s_name s_usage s_disable
      s_name="$(cat "${f}")"
      s_usage="$(cat "${f/name/usage}" 2>/dev/null || echo ?)"
      s_disable="$(cat "${f/name/disable}" 2>/dev/null || echo ?)"
      echo "  ${s_name}: usage=${s_usage}, disable=${s_disable}"
    done
    echo

    echo "=== Transparent Huge Pages ==="
    if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
      echo "THP enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
    fi
    if [[ -f /sys/kernel/mm/transparent_hugepage/defrag ]]; then
      echo "THP defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag)"
    fi
    echo

    echo "=== NUMA balancing ==="
    if [[ -f /proc/sys/kernel/numa_balancing ]]; then
      echo "numa_balancing: $(cat /proc/sys/kernel/numa_balancing)"
    fi
    echo

    echo "=== IRQ affinity (server CPUs: ${SERVER_CPUSET}) ==="
    if [[ "${ENABLE_SUDO}" == "1" ]]; then
      for irq in /proc/irq/*/smp_affinity_list; do
        [[ -f "${irq}" ]] || continue
        local irq_num irq_aff
        irq_num="$(basename "$(dirname "${irq}")")"
        irq_aff="$(cat "${irq}" 2>/dev/null || echo '?')"
        echo "  IRQ ${irq_num}: ${irq_aff}"
      done 2>/dev/null || echo "  (cannot read IRQ affinity without sudo)"
    else
      echo "  (skipped: ENABLE_SUDO=0)"
    fi
    echo

    echo "=== Memory info ==="
    cat /proc/meminfo 2>/dev/null || true
    echo

    echo "=== Topology ==="
    lscpu 2>/dev/null || true
    echo
    lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE 2>/dev/null || true
    echo
    numactl -H 2>/dev/null || true
    echo

    echo "=== Interrupts (snapshot) ==="
    cat /proc/interrupts 2>/dev/null | head -30 || true
    echo

    echo "=== Kernel ==="
    uname -a
    echo

    echo "=== Docker ==="
    docker version 2>/dev/null || true
    echo
    docker info 2>/dev/null | grep -E 'Server Version|CPUs|Total Memory|Operating System|Cgroup' || true
    echo

  } > "${PREFLIGHT_LOG}" 2>&1

  log "System state captured to ${PREFLIGHT_LOG}"
}

# ----------------------------
# CPU frequency locking
# ----------------------------

lock_cpu_frequency() {
  if [[ "${CPU_FREQ_LOCK:-0}" != "1" ]]; then
    log "CPU_FREQ_LOCK=0, not locking CPU frequency."
    log "  Current governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
    return 0
  fi

  if [[ "${ENABLE_SUDO}" != "1" ]]; then
    log "ENABLE_SUDO=0, cannot lock CPU frequency."
    return 0
  fi

  local governor="${CPU_FREQ_GOVERNOR:-performance}"
  log "Locking CPU frequency: governor=${governor}"

  if ! command -v cpupower &>/dev/null; then
    log "WARNING: cpupower not found, cannot set CPU governor."
    return 0
  fi

  sudo -n cpupower frequency-set -g "${governor}" || {
    log "WARNING: failed to set CPU governor to ${governor}"
    return 0
  }

  log "CPU governor set to ${governor}"
}

# ----------------------------
# Time budget calculation
# ----------------------------

calculate_time_budget() {
  local num_conditions
  num_conditions="$(tail -n +2 "${MATRIX_FILE}" | grep -cv '^[[:space:]]*$' || echo 0)"
  local num_baselines=$((num_conditions / BASELINE_INTERVAL + 2))

  # Each client run = warmup_time + test_time. Prewarm uses same client.
  local client_duration=$((CLIENT_WARMUP_TIME + CLIENT_TEST_TIME))
  local prewarm_duration=$((CLIENT_WARMUP_TIME + PREWARM_TEST_TIME))
  local prewarm_time=$((PREWARM_ROUNDS * (prewarm_duration + 10) + SERVER_BOOTSTRAP_WAIT))
  local sweep_time=$((num_conditions * (client_duration + OFFLINE_STABILIZE_WAIT + OFFLINE_COOLDOWN_WAIT + 10)))
  local baseline_time=$((num_baselines * (client_duration + 5)))
  local estimated_total=$((prewarm_time + sweep_time + baseline_time))

  local server_total=$((TAO_SERVER_WARMUP_TIME + TAO_SERVER_TEST_TIME))

  log "=== Time budget ==="
  log "  Conditions in matrix:   ${num_conditions}"
  log "  Estimated baselines:    ${num_baselines}"
  log "  Prewarm+bootstrap:      ${prewarm_time}s ($((prewarm_time / 60))m)"
  log "  Sweep (conditions):     ${sweep_time}s ($((sweep_time / 60))m)"
  log "  Baselines:              ${baseline_time}s ($((baseline_time / 60))m)"
  log "  Estimated total:        ${estimated_total}s ($((estimated_total / 60))m = $((estimated_total / 3600))h)"
  log "  Server total lifetime:  ${server_total}s ($((server_total / 60))m = $((server_total / 3600))h)"
  log "  Server warmup:          ${TAO_SERVER_WARMUP_TIME}s"
  log "  Server test time:       ${TAO_SERVER_TEST_TIME}s"
  log "  Available after warmup: $((server_total - TAO_SERVER_WARMUP_TIME - SERVER_BOOTSTRAP_WAIT))s"

  if [[ "${estimated_total}" -gt "$((server_total - SERVER_BOOTSTRAP_WAIT))" ]]; then
    log "  *** WARNING: estimated time EXCEEDS server lifetime! ***"
    log "  *** Increase TAO_SERVER_TEST_TIME (currently ${TAO_SERVER_TEST_TIME}s) or reduce matrix. ***"
    log "  *** Suggested TAO_SERVER_TEST_TIME >= $((estimated_total + SERVER_BOOTSTRAP_WAIT - TAO_SERVER_WARMUP_TIME + 600)) ***"
  else
    local margin=$((server_total - SERVER_BOOTSTRAP_WAIT - estimated_total))
    log "  Margin: ${margin}s ($((margin / 60))m) -- OK"
  fi
  log "========================"
}

# ----------------------------
# Container binding verification
# ----------------------------

verify_container_binding() {
  local container="$1"
  local expected_cpuset="$2"
  local expected_mems="$3"
  local label="$4"

  local actual_cpuset actual_mems
  actual_cpuset="$(docker inspect "${container}" --format '{{.HostConfig.CpusetCpus}}' 2>/dev/null || echo '')"
  actual_mems="$(docker inspect "${container}" --format '{{.HostConfig.CpusetMems}}' 2>/dev/null || echo '')"

  if [[ "${actual_cpuset}" != "${expected_cpuset}" ]]; then
    die "Container ${container} (${label}) cpuset MISMATCH: expected=${expected_cpuset}, actual=${actual_cpuset}"
  fi
  if [[ "${actual_mems}" != "${expected_mems}" ]]; then
    die "Container ${container} (${label}) mems MISMATCH: expected=${expected_mems}, actual=${actual_mems}"
  fi

  log "Container ${container} (${label}) binding verified: cpuset=${actual_cpuset}, mems=${actual_mems}"
}

# ----------------------------
# Sudo keepalive
# ----------------------------

start_sudo_keepalive() {
  if [[ "${ENABLE_SUDO}" != "1" ]]; then
    return 0
  fi
  # Use sudo -n (non-interactive) to check. sudo -v would HANG in nohup/TTY-less env.
  if ! sudo -n true 2>/dev/null; then
    log "WARNING: sudo non-interactive check failed. Running without sudo."
    ENABLE_SUDO=0
    return 0
  fi
  (
    while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

# ----------------------------
# Container management
# ----------------------------

create_containers() {
  log "Creating TaoBench server container..."
  bash "${CBS_ROOT}/containers/create_taobench_server.sh"
  verify_container_binding "${SERVER_CONTAINER}" "${SERVER_CPUSET}" "${SERVER_MEMS}" "server"

  log "Creating TaoBench loadgen container..."
  bash "${CBS_ROOT}/containers/create_taobench_loadgen.sh"
  verify_container_binding "${LOADGEN_CONTAINER}" "${LOADGEN_CPUSET}" "${LOADGEN_MEMS}" "loadgen"

  log "Creating offline container..."
  bash "${CBS_ROOT}/containers/create_offline.sh"
  verify_container_binding "${OFFLINE_CONTAINER}" "${OFFLINE_CPUSET}" "${OFFLINE_MEMS}" "offline"

  docker inspect "${SERVER_CONTAINER}" \
    > "${RUN_DIR}/machine_topology/server_container.inspect.json" 2>/dev/null || true
  docker inspect "${LOADGEN_CONTAINER}" \
    > "${RUN_DIR}/machine_topology/loadgen_container.inspect.json" 2>/dev/null || true
  docker inspect "${OFFLINE_CONTAINER}" \
    > "${RUN_DIR}/machine_topology/offline_container.inspect.json" 2>/dev/null || true

  log "All containers created and bindings verified."
}

recreate_offline_container() {
  cleanup_offline || true
  bash "${CBS_ROOT}/containers/create_offline.sh"
  verify_container_binding "${OFFLINE_CONTAINER}" "${OFFLINE_CPUSET}" "${OFFLINE_MEMS}" "offline"
}

# ----------------------------
# TaoBench server / client
# ----------------------------

start_taobench_server() {
  local server_log="/workspace/results/$(basename "${RUN_DIR}")/logs/server.log"
  log "Starting TaoBench server..."
  bash "${CBS_ROOT}/online/taobench/start_server.sh" \
    "${server_log}" \
    "${TAO_SERVER_WARMUP_TIME}" \
    "${TAO_SERVER_TEST_TIME}"
  log "Waiting for server bootstrap: ${SERVER_BOOTSTRAP_WAIT}s"
  sleep "${SERVER_BOOTSTRAP_WAIT}"
}

run_client_and_parse() {
  local phase_label="$1"
  local condition_id="$2"
  local repeat_id="$3"
  local clients="$4"
  local test_time="$5"
  local log_file="$6"
  local json_file="$7"

  log "Client run: phase=${phase_label}, condition=${condition_id}, repeat=${repeat_id}, clients=${clients}, test_time=${test_time}"

  # Timeout = warmup + test + 2min buffer to prevent hanging if server dies
  local deadline=$((CLIENT_WARMUP_TIME + test_time + 120))

  timeout "${deadline}" bash "${CBS_ROOT}/online/taobench/run_client.sh" \
    "${clients}" \
    "${test_time}" \
    "${log_file}" || {
      local ec=$?
      if [[ "${ec}" == "124" ]]; then
        log "ERROR: client run timed out after ${deadline}s for ${condition_id}"
      else
        log "WARNING: client run failed (exit ${ec}) for ${condition_id}"
      fi
      return 1
    }

  python3 "${CBS_ROOT}/parsers/parse_taobench_client.py" \
    "${log_file}" \
    --json-out "${json_file}" || true
}

full_prewarm() {
  log "Starting full prewarm: rounds=${PREWARM_ROUNDS}, clients=${PREWARM_CLIENTS}, test_time=${PREWARM_TEST_TIME}"

  for round in $(seq 1 "${PREWARM_ROUNDS}"); do
    local client_log="${RUN_DIR}/raw/full_prewarm_round_${round}.log"
    local client_json="${RUN_DIR}/parsed/full_prewarm_round_${round}.json"

    if ! run_client_and_parse "full_prewarm" "initial" "${round}" "${PREWARM_CLIENTS}" "${PREWARM_TEST_TIME}" "${client_log}" "${client_json}"; then
      die "Full prewarm failed at round ${round}/${PREWARM_ROUNDS}"
    fi

    local qps
    qps="$(parse_json_field "${client_json}" qps)"
    log "Full prewarm round ${round}/${PREWARM_ROUNDS}: qps=${qps}"
    sleep 10
  done
}

# ----------------------------
# Offline workload dispatch
# ----------------------------

start_offline_workload() {
  local offline_type="$1"
  local offline_param="$2"
  local offline_intensity="$3"
  local offline_log="$4"
  local spec_size="$5"
  local spec_copies="$6"
  local spec_bench="$7"

  case "${offline_type}" in
    none)
      log "No offline workload."
      ;;
    ibench_cpu)
      IBENCH_CPU_ARG="${offline_intensity:-30}" \
        bash "${CBS_ROOT}/offline/ibench/start_cpu.sh" "${offline_param:-8}" "${offline_log}"
      ;;
    ibench_membw)
      IBENCH_MEMBW_ARG="${offline_intensity:-30}" \
        bash "${CBS_ROOT}/offline/ibench/start_membw.sh" "${offline_param:-8}" "${offline_log}"
      ;;
    ibench_l3)
      IBENCH_L3_ARG="${offline_intensity:-30}" \
        bash "${CBS_ROOT}/offline/ibench/start_l3.sh" "${offline_param:-8}" "${offline_log}"
      ;;
    ibench_memcap)
      bash "${CBS_ROOT}/offline/ibench/start_memcap.sh" "${offline_param:-15}" "${offline_log}"
      ;;
    spec)
      [[ -n "${spec_bench}" ]] || die "spec requires spec_bench"
      [[ -n "${spec_size}" ]] || die "spec requires spec_size"
      [[ -n "${spec_copies}" ]] || die "spec requires spec_copies"
      log "Starting SPEC: bench=${spec_bench}, size=${spec_size}, copies=${spec_copies}"
      SPEC_COPIES="${spec_copies}" bash "${CBS_ROOT}/offline/spec/start_runcpu.sh" \
        "${spec_bench}" "${offline_log}" "${spec_size}" "${SPEC_CONFIG}"
      ;;
    *)
      die "Unknown offline_type=${offline_type}"
      ;;
  esac
}

# ----------------------------
# Condition execution
# ----------------------------

TMP_RESULT="${RUN_DIR}/progress/.tmp_result"

run_measured_client_for_condition() {
  local condition_id="$1"
  local repeat_id="$2"

  local client_log="${RUN_DIR}/raw/${condition_id}_repeat_${repeat_id}.log"
  local client_json="${RUN_DIR}/parsed/${condition_id}_repeat_${repeat_id}.json"

  if ! run_client_and_parse "measured" "${condition_id}" "${repeat_id}" "${CLIENTS}" "${CLIENT_TEST_TIME}" "${client_log}" "${client_json}"; then
    return 1
  fi

  local qps p99
  qps="$(parse_json_field "${client_json}" qps)"
  p99="$(parse_json_field "${client_json}" gets_p99_ms)"
  # Write to temp file to avoid stdout pollution from child log() calls
  echo "${qps}|${p99}|${client_log}|${client_json}" > "${TMP_RESULT}"
}

run_condition() {
  local condition_id="$1"
  local offline_type="$2"
  local offline_param="$3"
  local offline_intensity="$4"
  local offline_label="$5"
  local spec_size="$6"
  local spec_copies="$7"
  local spec_bench="$8"

  local offline_log="/workspace/results/$(basename "${RUN_DIR}")/logs/offline_${condition_id}.log"

  log "============================================================"
  log "Condition: ${condition_id}"
  log "  offline_type=${offline_type}, param=${offline_param}, intensity=${offline_intensity}, label=${offline_label}"
  log "  spec: size=${spec_size}, copies=${spec_copies}, bench=${spec_bench}"
  log "============================================================"

  recreate_offline_container

  start_offline_workload "${offline_type}" "${offline_param}" "${offline_intensity}" "${offline_log}" "${spec_size}" "${spec_copies}" "${spec_bench}"

  if [[ "${offline_type}" != "none" ]]; then
    log "Waiting for offline workload to stabilize: ${OFFLINE_STABILIZE_WAIT}s"
    sleep 5
    # Verify workload is actually running before full stabilize wait
    local procs
    procs="$(docker top "${OFFLINE_CONTAINER}" 2>/dev/null | wc -l || echo 0)"
    if [[ "${procs}" -lt 3 ]]; then
      log "WARNING: only ${procs} processes in offline container. Offline workload may not have started!"
      record_failure "${condition_id}" "offline_maybe_not_started_${procs}_procs"
    fi
    sleep $((OFFLINE_STABILIZE_WAIT - 5))
  fi

  local best_qps="" best_p99="" best_log="" best_json=""
  local all_failed=1

  for repeat_id in $(seq 1 "${MEASURE_REPEATS}"); do
    local r_qps r_p99 r_log r_json
    if run_measured_client_for_condition "${condition_id}" "${repeat_id}"; then
      all_failed=0
      r_qps="$(cut -d'|' -f1 "${TMP_RESULT}")"
      r_p99="$(cut -d'|' -f2 "${TMP_RESULT}")"
      r_log="$(cut -d'|' -f3 "${TMP_RESULT}")"
      r_json="$(cut -d'|' -f4 "${TMP_RESULT}")"
      log "  repeat ${repeat_id}: qps=${r_qps}, p99=${r_p99}"

      best_qps="${r_qps}"
      best_p99="${r_p99}"
      best_log="${r_log}"
      best_json="${r_json}"

      if [[ "${repeat_id}" != "${MEASURE_REPEATS}" ]]; then
        sleep "${MEASURE_GAP}"
      fi
    else
      log "  WARNING: repeat ${repeat_id} failed for ${condition_id}"
    fi
  done

  if [[ "${all_failed}" == "1" ]]; then
    log "ERROR: all repeats failed for ${condition_id}"
    record_failure "${condition_id}" "all_repeats_failed"
    if [[ "${offline_type}" != "none" ]]; then
      cleanup_offline || true
    fi
    return 1
  fi

  csv_append_row \
    "$(date -Iseconds)" \
    "${EXP_NAME}" \
    "${PLACEMENT}" \
    "${condition_id}" \
    "1" \
    "${offline_type}" \
    "${offline_param}" \
    "${offline_intensity}" \
    "${offline_label}" \
    "${spec_size}" \
    "${spec_copies}" \
    "${spec_bench}" \
    "${CLIENTS}" \
    "${CLIENT_TEST_TIME}" \
    "${CLIENT_WARMUP_TIME}" \
    "${SERVER_CPUSET}" \
    "${SERVER_MEMS}" \
    "${LOADGEN_CPUSET}" \
    "${LOADGEN_MEMS}" \
    "${OFFLINE_CPUSET}" \
    "${OFFLINE_MEMS}" \
    "${best_qps}" \
    "${best_p99}" \
    "${best_log}" \
    "${best_json}" \
    "${offline_log}" \
    "${RUN_DIR}" \
    ""

  if [[ "${offline_type}" != "none" ]]; then
    log "Stopping offline workload after ${condition_id}"
    cleanup_offline || true
  fi

  sleep "${OFFLINE_COOLDOWN_WAIT}"

  save_progress "${condition_id}"
  log "Condition ${condition_id} completed."
}

run_baseline_checkpoint() {
  local label="$1"
  local condition_id="baseline_${label}"

  log "Running baseline checkpoint: ${condition_id}"

  local offline_log="/workspace/results/$(basename "${RUN_DIR}")/logs/offline_${condition_id}.log"

  if run_measured_client_for_condition "${condition_id}" "1"; then
    local r_qps r_p99 r_log r_json
    r_qps="$(cut -d'|' -f1 "${TMP_RESULT}")"
    r_p99="$(cut -d'|' -f2 "${TMP_RESULT}")"
    r_log="$(cut -d'|' -f3 "${TMP_RESULT}")"
    r_json="$(cut -d'|' -f4 "${TMP_RESULT}")"

    csv_append_row \
      "$(date -Iseconds)" \
      "${EXP_NAME}" \
      "${PLACEMENT}" \
      "${condition_id}" \
      "1" \
      "none" \
      "" "" "none" "" "" "" \
      "${CLIENTS}" \
      "${CLIENT_TEST_TIME}" \
      "${CLIENT_WARMUP_TIME}" \
      "${SERVER_CPUSET}" \
      "${SERVER_MEMS}" \
      "${LOADGEN_CPUSET}" \
      "${LOADGEN_MEMS}" \
      "${OFFLINE_CPUSET}" \
      "${OFFLINE_MEMS}" \
      "${r_qps}" \
      "${r_p99}" \
      "${r_log}" \
      "${r_json}" \
      "${offline_log}" \
      "${RUN_DIR}" \
      ""

    log "Baseline ${condition_id}: qps=${r_qps}, p99=${r_p99}"
    save_progress "${condition_id}"
  else
    log "WARNING: baseline checkpoint ${condition_id} failed"
    record_failure "${condition_id}" "baseline_client_failed"
  fi

  sleep 5
}

# ----------------------------
# Matrix reader
# ----------------------------

read_matrix() {
  tail -n +2 "${MATRIX_FILE}" | grep -v '^[[:space:]]*$'
}

# ----------------------------
# Main sweep
# ----------------------------

run_sweep() {
  log "Reading condition matrix: ${MATRIX_FILE}"

  if [[ ! -f "${MATRIX_FILE}" ]]; then
    die "MATRIX_FILE not found: ${MATRIX_FILE}"
  fi

  # Validate CSV has required columns (prevents format mismatch bugs)
  local header
  header="$(head -1 "${MATRIX_FILE}")"
  for col in condition_id offline_type offline_param offline_intensity offline_label spec_size spec_copies spec_bench; do
    if ! echo "${header}" | grep -qF "${col}"; then
      die "MATRIX_FILE missing required column: ${col}. Regenerate with tools/generate_stage1_matrix.py"
    fi
  done
  log "Matrix schema validated: ${header}"

  local completed
  completed="$(load_completed)"

  local total=0 skipped=0 ran=0 failed=0 since_last_baseline=0

  while IFS=',' read -r condition_id offline_type offline_param offline_intensity offline_label spec_size spec_copies spec_bench rest; do
    [[ "${condition_id}" == "condition_id" ]] && continue
    [[ -z "${condition_id}" ]] && continue

    total=$((total + 1))

    if echo "${completed}" | grep -qFx "${condition_id}"; then
      skipped=$((skipped + 1))
      log "[${total}] SKIP ${condition_id} (already completed)"
      continue
    fi

    if [[ "${since_last_baseline}" -ge "${BASELINE_INTERVAL}" ]]; then
      local baseline_label="auto_$(printf '%03d' $((total - 1)))"
      run_baseline_checkpoint "${baseline_label}"
      since_last_baseline=0
    fi

    log "[${total}] RUN ${condition_id}"

    if run_condition "${condition_id}" "${offline_type}" "${offline_param}" "${offline_intensity}" "${offline_label}" "${spec_size}" "${spec_copies}" "${spec_bench}"; then
      ran=$((ran + 1))
      since_last_baseline=$((since_last_baseline + 1))
    else
      failed=$((failed + 1))
      log "WARNING: condition ${condition_id} failed, continuing to next"
    fi

    log "Progress: ${ran} ran, ${failed} failed, ${skipped} skipped, ${total} total in matrix"
  done < <(read_matrix)

  log "============================================================"
  log "Sweep complete: ${ran} ran, ${failed} failed, ${skipped} skipped, ${total} total"
  log "Summary: ${SUMMARY}"
  log "Failures: ${FAILURES_FILE}"
  log "Run directory: ${RUN_DIR}"
}

# ----------------------------
# Main
# ----------------------------

log "=== Stage 1-A Clean Sweep ==="
log "PLACEMENT=${PLACEMENT}"
log "EXP_NAME=${EXP_NAME}"
log "MATRIX_FILE=${MATRIX_FILE}"
log "Run directory: ${RUN_DIR}"
log "Placement: server=${SERVER_CPUSET}/${SERVER_MEMS}, loadgen=${LOADGEN_CPUSET}/${LOADGEN_MEMS}, offline=${OFFLINE_CPUSET}/${OFFLINE_MEMS}"

capture_system_state
calculate_time_budget
lock_cpu_frequency

write_summary_header

start_sudo_keepalive
create_containers

log "Applying network sysctl..."
if [[ "${ENABLE_SUDO}" == "1" ]]; then
  sudo -n sysctl -w net.ipv4.ip_local_port_range="1024 65535" || true
  sudo -n sysctl -w net.ipv4.tcp_tw_reuse=1 || true
  sudo -n sysctl -w net.ipv4.tcp_fin_timeout=15 || true
fi

start_taobench_server
full_prewarm

run_baseline_checkpoint "initial"

# Verify baseline QPS is valid (guard against dead server / port conflict)
_baseline_qps=$(tail -1 "${SUMMARY}" | awk -F',' '{print $18}' 2>/dev/null || echo 0)
if [[ "${_baseline_qps}" == "0.0" || "${_baseline_qps}" == "0" || -z "${_baseline_qps}" ]]; then
  die "Baseline QPS is ${_baseline_qps:-0}. Server appears dead or not accepting connections. Check server logs in ${RUN_DIR}/logs/"
fi
log "Baseline QPS validated: ${_baseline_qps}"

run_sweep

run_baseline_checkpoint "final"

log "=== Stage 1-A completed successfully ==="
log "Summary: ${SUMMARY}"
log "Run directory: ${RUN_DIR}"
