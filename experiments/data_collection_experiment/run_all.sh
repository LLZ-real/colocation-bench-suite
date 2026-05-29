#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Stage 1-A Master Runner: one command to run all experiments.
#
# Usage:
#   bash experiments/data_collection_experiment/run_all.sh [mode]
#
# Modes:
#   ibench     iBench only (3 placements x 45 conditions, ~8h)
#   spec       SPEC only  (3 placements x 57 conditions, ~15h)
#   all        Everything (default, ~24h)
#   smoke      Quick smoke test (~5min)
#   list       Print what would run, don't execute
#
# Resume: re-run the same command to skip already-completed placements.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

MODE="${1:-all}"

# ----------------------------
# Configuration
# ----------------------------

CLAB_IMAGE="${CLAB_IMAGE:-dcperf-taobench:ready}"
DCPERF_MOUNT="${DCPERF_MOUNT:-0}"
RESULTS_ROOT="${RESULTS_ROOT:-/home/lilinzhen/colocate_lab/results/cbs}"
MATRIX_DIR="${CBS_ROOT}/docs"

SERVER_CPUSET="0,1,2,3,4,5,6,7"
SERVER_MEMS="0"
LOADGEN_CPUSET="32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47"
LOADGEN_MEMS="1"

CLIENTS_PER_THREAD=900
CLIENT_TEST_TIME=60
CLIENT_WARMUP_TIME=120
PREWARM_ROUNDS=8
PREWARM_TEST_TIME=60

TAO_SERVER_WARMUP_TIME=2400
SERVER_BOOTSTRAP_WAIT=180
OFFLINE_STABILIZE_WAIT=30
OFFLINE_COOLDOWN_WAIT=5
BASELINE_INTERVAL=10

MEASURE_REPEATS=1
MEASURE_GAP=5

SPEC_CONFIG="my_test.cfg"

# iBench: 45 conditions, ~3.6h per placement (client 120s warmup + 60s test)
IBENCH_TAO_TEST_TIME=18000
# SPEC: 57 conditions, ~4.5h per placement
SPEC_TAO_TEST_TIME=21600

# ----------------------------
# Matrix generation
# ----------------------------

generate_matrices() {
  local gen="${CBS_ROOT}/tools/generate_stage1_matrix.py"
  echo "[generate] creating iBench matrix (force regenerate)..."
  python3 "${gen}" --mode ibench --out "${MATRIX_DIR}/stage1_ibench_matrix.csv"
  echo "[generate] creating SPEC matrix (force regenerate)..."
  python3 "${gen}" --mode spec --out "${MATRIX_DIR}/stage1_spec_matrix.csv"
}

# ----------------------------
# Run a single experiment (with resume support)
# ----------------------------

DONE_DIR="${RESULTS_ROOT}/.stage1_done_placements"
mkdir -p "${DONE_DIR}"

is_placement_done() {
  [[ -f "${DONE_DIR}/$1" ]]
}

mark_placement_done() {
  touch "${DONE_DIR}/$1"
  echo "[done] placement $1 marked complete"
}

run_one() {
  local placement="$1"
  local matrix_file="$2"
  local exp_name="$3"
  local tao_test_time="$4"

  if is_placement_done "${exp_name}"; then
    echo ""
    echo "================================================================================"
    echo "  SKIP: ${exp_name} (already completed)"
    echo "================================================================================"
    return 0
  fi

  echo ""
  echo "================================================================================"
  echo "  START: ${exp_name}"
  echo "  Placement: ${placement}"
  echo "  Matrix:    ${matrix_file}"
  echo "  Started:   $(date -Iseconds)"
  echo "================================================================================"

  local ec=0
  MATRIX_FILE="${matrix_file}" \
    PLACEMENT="${placement}" \
    EXP_NAME="${exp_name}" \
    CLAB_IMAGE="${CLAB_IMAGE}" \
    DCPERF_MOUNT="${DCPERF_MOUNT}" \
    RESULTS_ROOT="${RESULTS_ROOT}" \
    SERVER_CPUSET="${SERVER_CPUSET}" \
    SERVER_MEMS="${SERVER_MEMS}" \
    LOADGEN_CPUSET="${LOADGEN_CPUSET}" \
    LOADGEN_MEMS="${LOADGEN_MEMS}" \
    CLIENTS_PER_THREAD="${CLIENTS_PER_THREAD}" \
    CLIENT_TEST_TIME="${CLIENT_TEST_TIME}" \
    CLIENT_WARMUP_TIME="${CLIENT_WARMUP_TIME}" \
    PREWARM_ROUNDS="${PREWARM_ROUNDS}" \
    PREWARM_TEST_TIME="${PREWARM_TEST_TIME}" \
    TAO_SERVER_WARMUP_TIME="${TAO_SERVER_WARMUP_TIME}" \
    TAO_SERVER_TEST_TIME="${tao_test_time}" \
    SERVER_BOOTSTRAP_WAIT="${SERVER_BOOTSTRAP_WAIT}" \
    OFFLINE_STABILIZE_WAIT="${OFFLINE_STABILIZE_WAIT}" \
    OFFLINE_COOLDOWN_WAIT="${OFFLINE_COOLDOWN_WAIT}" \
    BASELINE_INTERVAL="${BASELINE_INTERVAL}" \
    MEASURE_REPEATS="${MEASURE_REPEATS}" \
    MEASURE_GAP="${MEASURE_GAP}" \
    SPEC_CONFIG="${SPEC_CONFIG}" \
    bash "${SCRIPT_DIR}/stage1_sweep_clean.sh" || ec=$?
  echo "================================================================================"
  if [[ "${ec}" == "0" ]]; then
    echo "  DONE:  ${exp_name}"
    mark_placement_done "${exp_name}"
  else
    echo "  FAIL:  ${exp_name} (exit code ${ec})"
  fi
  echo "  Ended: $(date -Iseconds)"
  echo "================================================================================"
}

# ----------------------------
# Smoke test
# ----------------------------

run_smoke() {
  echo "[smoke] creating test matrix..."
  local smoke_csv="/tmp/stage1_smoke_matrix.csv"
  cat > "${smoke_csv}" <<'EOF'
condition_id,offline_type,offline_param,offline_intensity,offline_label,spec_size,spec_copies,spec_bench,workload_category,resource_profile
ibench_cpu_w1_a30,ibench_cpu,1,30,w1_a30,,,,ibench,cpu
none_baseline,none,,,none,,,,none,
EOF

  echo "[smoke] running quick verification (same_numa only)..."
  run_one "same_numa" "${smoke_csv}" "stage1_smoke" 600
}

# ----------------------------
# Main dispatch
# ----------------------------

echo "=== Stage 1-A Master Runner ==="
echo "Mode: ${MODE}"
echo "Started: $(date -Iseconds)"
echo

generate_matrices

case "${MODE}" in
  smoke)
    run_smoke || true
    ;;
  list)
    echo "Would run:"
    echo "  1. same_numa  iBench  (${MATRIX_DIR}/stage1_ibench_matrix.csv)"
    echo "  2. cross_numa iBench"
    echo "  3. same_smt   iBench"
    echo "  4. same_numa  SPEC    (${MATRIX_DIR}/stage1_spec_matrix.csv)"
    echo "  5. cross_numa SPEC"
    echo "  6. same_smt   SPEC"
    ;;
  ibench)
    run_one same_numa  "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_same_numa"  "${IBENCH_TAO_TEST_TIME}" || true
    run_one cross_numa "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_cross_numa" "${IBENCH_TAO_TEST_TIME}" || true
    run_one same_smt   "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_same_smt"   "${IBENCH_TAO_TEST_TIME}" || true
    ;;
  spec)
    run_one same_numa  "${MATRIX_DIR}/stage1_spec_matrix.csv" "stage1_sail3090_spec_same_numa"  "${SPEC_TAO_TEST_TIME}" || true
    run_one cross_numa "${MATRIX_DIR}/stage1_spec_matrix.csv" "stage1_sail3090_spec_cross_numa" "${SPEC_TAO_TEST_TIME}" || true
    run_one same_smt   "${MATRIX_DIR}/stage1_spec_matrix.csv" "stage1_sail3090_spec_same_smt"   "${SPEC_TAO_TEST_TIME}" || true
    ;;
  all)
    run_one same_numa  "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_same_numa"  "${IBENCH_TAO_TEST_TIME}" || true
    run_one cross_numa "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_cross_numa" "${IBENCH_TAO_TEST_TIME}" || true
    run_one same_smt   "${MATRIX_DIR}/stage1_ibench_matrix.csv" "stage1_sail3090_ibench_same_smt"   "${IBENCH_TAO_TEST_TIME}" || true
    run_one same_numa  "${MATRIX_DIR}/stage1_spec_matrix.csv"   "stage1_sail3090_spec_same_numa"    "${SPEC_TAO_TEST_TIME}" || true
    run_one cross_numa "${MATRIX_DIR}/stage1_spec_matrix.csv"   "stage1_sail3090_spec_cross_numa"   "${SPEC_TAO_TEST_TIME}" || true
    run_one same_smt   "${MATRIX_DIR}/stage1_spec_matrix.csv"   "stage1_sail3090_spec_same_smt"     "${SPEC_TAO_TEST_TIME}" || true
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    echo "Usage: bash experiments/data_collection_experiment/run_all.sh [ibench|spec|all|smoke|list]"
    exit 1
    ;;
esac

echo ""
echo "=== Stage 1-A Master Runner: ALL DONE ==="
echo "Ended: $(date -Iseconds)"
