#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

USER_DCPERF_REPO="${DCPERF_REPO:-}"
USER_DCPERF_REF="${DCPERF_REF:-}"
USER_DCPERF_DIR="${DCPERF_DIR:-}"
USER_DCPERF_CLONE_DEPTH="${DCPERF_CLONE_DEPTH:-}"
USER_UPDATE_EXISTING="${UPDATE_EXISTING:-}"
USER_TAOBENCH_INSTALL="${TAOBENCH_INSTALL:-}"
USER_BUILD_IMAGE="${BUILD_IMAGE:-}"
USER_REINSTALL_TAOBENCH="${REINSTALL_TAOBENCH:-}"
USER_PROXY="${PROXY:-${HTTP_PROXY:-${http_proxy:-}}}"

source "${CBS_ROOT}/scripts/common.sh"
if [[ -f "${CBS_ROOT}/conf/env.sh" ]]; then
  source "${CBS_ROOT}/conf/env.sh"
elif [[ -f "${CBS_ROOT}/conf/env.example.sh" ]]; then
  source "${CBS_ROOT}/conf/env.example.sh"
fi

DCPERF_REPO="${USER_DCPERF_REPO:-${DCPERF_REPO:-https://github.com/facebookresearch/DCPerf.git}}"
DCPERF_REF="${USER_DCPERF_REF:-${DCPERF_REF:-}}"
DCPERF_DIR="${USER_DCPERF_DIR:-${DCPERF_DIR:-/home/lilinzhen/colocate_lab/DCPerf}}"
DCPERF_CLONE_DEPTH="${USER_DCPERF_CLONE_DEPTH:-${DCPERF_CLONE_DEPTH:-1}}"
UPDATE_EXISTING="${USER_UPDATE_EXISTING:-${UPDATE_EXISTING:-0}}"
TAOBENCH_INSTALL="${USER_TAOBENCH_INSTALL:-${TAOBENCH_INSTALL:-1}}"
BUILD_IMAGE="${USER_BUILD_IMAGE:-${BUILD_IMAGE:-1}}"
REINSTALL_TAOBENCH="${USER_REINSTALL_TAOBENCH:-${REINSTALL_TAOBENCH:-0}}"
PROXY="${USER_PROXY:-${PROXY:-${HTTP_PROXY:-${http_proxy:-}}}}"

require_cmd git
require_cmd python3

if [[ -n "${PROXY}" ]]; then
  export http_proxy="${http_proxy:-${PROXY}}"
  export https_proxy="${https_proxy:-${PROXY}}"
  export HTTP_PROXY="${HTTP_PROXY:-${PROXY}}"
  export HTTPS_PROXY="${HTTPS_PROXY:-${PROXY}}"
  log "Using proxy: ${PROXY}"
fi

clone_dcperf() {
  local parent
  parent="$(dirname "${DCPERF_DIR}")"
  mkdir -p "${parent}"

  if [[ -d "${DCPERF_DIR}/.git" ]]; then
    log "DCPerf checkout already exists: ${DCPERF_DIR}"
    if [[ "${UPDATE_EXISTING}" == "1" ]]; then
      log "Updating existing DCPerf checkout"
      git -C "${DCPERF_DIR}" fetch --depth="${DCPERF_CLONE_DEPTH}" origin
      if [[ -n "${DCPERF_REF}" ]]; then
        git -C "${DCPERF_DIR}" fetch --depth="${DCPERF_CLONE_DEPTH}" origin "${DCPERF_REF}"
        git -C "${DCPERF_DIR}" checkout FETCH_HEAD
      else
        git -C "${DCPERF_DIR}" pull --ff-only
      fi
    fi
    return
  fi

  [[ ! -e "${DCPERF_DIR}" ]] || die "DCPERF_DIR exists but is not a git checkout: ${DCPERF_DIR}"

  log "Cloning DCPerf: ${DCPERF_REPO} -> ${DCPERF_DIR}"
  clone_args=(clone --depth "${DCPERF_CLONE_DEPTH}")
  if [[ -n "${DCPERF_REF}" ]]; then
    clone_args+=(--branch "${DCPERF_REF}")
  fi
  clone_args+=("${DCPERF_REPO}" "${DCPERF_DIR}")
  git "${clone_args[@]}"
}

install_python_deps() {
  log "Installing benchpress Python dependencies"
  python3 -m pip install --user --upgrade click pyyaml tabulate pandas 'numpy<2'
}

taobench_ready() {
  [[ -x "${DCPERF_DIR}/benchpress_cli.py" ]] || return 1
  [[ -d "${DCPERF_DIR}/packages/tao_bench" ]] || return 1
  [[ -d "${DCPERF_DIR}/benchmarks/tao_bench" ]] || return 1
  [[ -d "${DCPERF_DIR}/benchmarks/tao_bench_autoscale" ]] || return 1
  [[ -x "${DCPERF_DIR}/benchmarks/tao_bench/tao_bench_server" ]] || return 1
  [[ -x "${DCPERF_DIR}/benchmarks/tao_bench/tao_bench_client" ]] || return 1
}

install_taobench() {
  [[ -f "${DCPERF_DIR}/benchpress_cli.py" ]] || die "benchpress_cli.py not found in ${DCPERF_DIR}"
  chmod +x "${DCPERF_DIR}/benchpress_cli.py"

  if taobench_ready && [[ "${REINSTALL_TAOBENCH}" != "1" ]]; then
    log "TaoBench already appears installed; set REINSTALL_TAOBENCH=1 to force reinstall"
    return
  fi

  install_python_deps
  log "Installing TaoBench via benchpress; this can take a long time"
  (
    cd "${DCPERF_DIR}"
    ./benchpress_cli.py install tao_bench_autoscale
  )
}

validate_dcperf() {
  log "Validating DCPerf/TaoBench checkout"
  [[ -f "${DCPERF_DIR}/benchpress_cli.py" ]] || die "benchpress_cli.py not found in ${DCPERF_DIR}"
  [[ -d "${DCPERF_DIR}/packages/tao_bench" ]] || die "packages/tao_bench missing in ${DCPERF_DIR}"
  [[ -d "${DCPERF_DIR}/benchmarks/tao_bench" ]] || die "benchmarks/tao_bench missing in ${DCPERF_DIR}"
  [[ -d "${DCPERF_DIR}/benchmarks/tao_bench_autoscale" ]] || die "benchmarks/tao_bench_autoscale missing in ${DCPERF_DIR}"
  [[ -x "${DCPERF_DIR}/benchmarks/tao_bench/tao_bench_server" ]] || die "tao_bench_server missing; install did not complete"
  [[ -x "${DCPERF_DIR}/benchmarks/tao_bench/tao_bench_client" ]] || die "tao_bench_client missing; install did not complete"
}

clone_dcperf

if [[ "${TAOBENCH_INSTALL}" == "1" ]]; then
  install_taobench
fi

validate_dcperf

if [[ "${BUILD_IMAGE}" == "1" ]]; then
  log "Building portable TaoBench image from ${DCPERF_DIR}"
  DCPERF_DIR="${DCPERF_DIR}" PROXY="${PROXY}" bash "${CBS_ROOT}/scripts/build_taobench_image.sh"
else
  log "BUILD_IMAGE=0, skipping Docker image build"
fi

log "Bootstrap complete"
