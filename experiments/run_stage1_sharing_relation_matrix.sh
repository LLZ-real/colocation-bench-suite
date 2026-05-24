#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMMON_ENV=(
  ENABLE_PERF=0
  SERVER_BOOTSTRAP_WAIT=180
  PREWARM_ROUNDS=8
  PREWARM_CLIENTS=900
  PREWARM_TEST_TIME=60
  CLIENTS_PER_THREAD=900
  CLIENT_TEST_TIME=300
  CLIENT_WARMUP_TIME=120
  MEASURE_REPEATS=3
  MEASURE_GAP=30
  OFFLINE_STABILIZE_WAIT=60
)

run_case() {
  local relation="$1"
  local server_cpuset="$2"
  local server_mems="$3"
  local offline_cpuset="$4"
  local offline_mems="$5"
  local offline_type="$6"
  local offline_param="$7"
  local offline_label="$8"
  local spec_size="${9:-ref}"
  local spec_copies="${10:-8}"

  echo
  echo "============================================================"
  echo "[RELATION] ${relation}"
  echo "[WORKLOAD] ${offline_type} ${offline_label}"
  echo "[SERVER_CPUSET] ${server_cpuset}, mems=${server_mems}"
  echo "[OFFLINE_CPUSET] ${offline_cpuset}, mems=${offline_mems}"
  echo "============================================================"

  env "${COMMON_ENV[@]}" \
    SERVER_CPUSET="${server_cpuset}" \
    SERVER_MEMS="${server_mems}" \
    OFFLINE_CPUSET="${offline_cpuset}" \
    OFFLINE_MEMS="${offline_mems}" \
    SPEC_CONFIG=my_test.cfg \
    SPEC_SIZE="${spec_size}" \
    SPEC_COPIES="${spec_copies}" \
    EXP_NAME="stage1_share_${relation}_${offline_type}_${offline_label}" \
    OFFLINE_TYPE="${offline_type}" \
    OFFLINE_PARAM="${offline_param}" \
    OFFLINE_LABEL="${relation}_${offline_label}" \
    bash "${CBS_ROOT}/experiments/taobench_colocation_repeat_one.sh"
}

# 请根据 lscpu -e 修改这些 CPU 集合。
# 当前默认沿用 env.example.sh 的风格：
# server: socket0 physical cores
# offline_same_numa: socket0 different physical cores
# offline_cross_numa: socket1 physical/logical cores
# offline_reduced: socket0 fewer cores
SERVER_SAME="0,2,4,6,8,10,12,14"
SERVER_MEMS="0"

OFFLINE_SAME_NUMA="16,18,20,22,24,26,28,30"
OFFLINE_SAME_MEMS="0"

OFFLINE_CROSS_NUMA="1,3,5,7,9,11,13,15"
OFFLINE_CROSS_MEMS="1"

OFFLINE_REDUCED="16,18,20,22"
OFFLINE_REDUCED_MEMS="0"

# 如果要测 SMT sibling，请先用 lscpu -e 查 sibling 对。
# 下面只是占位例子，不确认拓扑前不要直接使用。
OFFLINE_SMT_SIBLING="32,34,36,38,40,42,44,46"
OFFLINE_SMT_MEMS="0"

WORKLOADS=(
  "ibench_membw 8 w8 ref 1"
  "ibench_l3 8 w8 ref 1"
  "spec_mcf '' ref_c8 ref 8"
  "spec_lbm '' ref_c8 ref 8"
)

for item in "${WORKLOADS[@]}"; do
  # shellcheck disable=SC2086
  set -- ${item}
  offline_type="$1"
  offline_param="$2"
  offline_label="$3"
  spec_size="$4"
  spec_copies="$5"

  run_case \
    "same_numa_diff_core" \
    "${SERVER_SAME}" "${SERVER_MEMS}" \
    "${OFFLINE_SAME_NUMA}" "${OFFLINE_SAME_MEMS}" \
    "${offline_type}" "${offline_param}" "${offline_label}" "${spec_size}" "${spec_copies}"

  run_case \
    "cross_numa" \
    "${SERVER_SAME}" "${SERVER_MEMS}" \
    "${OFFLINE_CROSS_NUMA}" "${OFFLINE_CROSS_MEMS}" \
    "${offline_type}" "${offline_param}" "${offline_label}" "${spec_size}" "${spec_copies}"

  run_case \
    "reduced_offline_cores" \
    "${SERVER_SAME}" "${SERVER_MEMS}" \
    "${OFFLINE_REDUCED}" "${OFFLINE_REDUCED_MEMS}" \
    "${offline_type}" "${offline_param}" "${offline_label}" "${spec_size}" "${spec_copies}"

  # 确认 SMT sibling 后再打开。
  # run_case \
  #   "same_smt_sibling" \
  #   "${SERVER_SAME}" "${SERVER_MEMS}" \
  #   "${OFFLINE_SMT_SIBLING}" "${OFFLINE_SMT_MEMS}" \
  #   "${offline_type}" "${offline_param}" "${offline_label}" "${spec_size}" "${spec_copies}"
done