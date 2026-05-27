#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${CBS_ROOT}/scripts/common.sh"
if [[ -f "${CBS_ROOT}/conf/env.sh" ]]; then
  source "${CBS_ROOT}/conf/env.sh"
elif [[ -f "${CBS_ROOT}/conf/env.example.sh" ]]; then
  source "${CBS_ROOT}/conf/env.example.sh"
fi

IMAGE_NAME="${IMAGE_NAME:-dcperf-taobench}"
IMAGE_TAG="${IMAGE_TAG:-ready}"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
DCPERF_DIR="${DCPERF_DIR:-/home/lilinzhen/colocate_lab/DCPerf}"
BUILD_CONTEXT="${BUILD_CONTEXT:-}"
KEEP_BUILD_CONTEXT="${KEEP_BUILD_CONTEXT:-0}"
DOCKER_BUILD_NETWORK="${DOCKER_BUILD_NETWORK:-host}"
PROXY="${PROXY:-${HTTP_PROXY:-${http_proxy:-}}}"
APT_MIRROR="${APT_MIRROR:-http://mirrors.aliyun.com/ubuntu}"

require_cmd docker
require_cmd rsync

[[ -d "${DCPERF_DIR}" ]] || die "DCPERF_DIR does not exist: ${DCPERF_DIR}"
[[ -f "${DCPERF_DIR}/benchpress_cli.py" ]] || die "benchpress_cli.py not found in ${DCPERF_DIR}"
[[ -d "${DCPERF_DIR}/benchmarks/tao_bench" ]] || die "TaoBench benchmark missing: ${DCPERF_DIR}/benchmarks/tao_bench"
[[ -d "${DCPERF_DIR}/benchmarks/tao_bench_autoscale" ]] || die "TaoBench autoscale benchmark missing: ${DCPERF_DIR}/benchmarks/tao_bench_autoscale"
[[ -d "${DCPERF_DIR}/packages/tao_bench" ]] || die "TaoBench package missing: ${DCPERF_DIR}/packages/tao_bench"

if [[ -z "${BUILD_CONTEXT}" ]]; then
  BUILD_CONTEXT="$(mktemp -d /tmp/dcperf-taobench-build.XXXXXX)"
fi

cleanup() {
  if [[ "${KEEP_BUILD_CONTEXT}" != "1" && -d "${BUILD_CONTEXT}" ]]; then
    rm -rf "${BUILD_CONTEXT}"
  fi
}
trap cleanup EXIT

log "Preparing Docker build context: ${BUILD_CONTEXT}"
mkdir -p "${BUILD_CONTEXT}/DCPerf" "${BUILD_CONTEXT}/host-libs"

log "Copying DCPerf root files and TaoBench-only directories"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  --exclude 'benchmark_metrics_*/' \
  --exclude 'results/' \
  --exclude 'logs/' \
  --exclude '*.log' \
  --exclude 'client_*.log' \
  --exclude 'server*.log' \
  --exclude 'tao-bench-server-*.log' \
  --exclude '*.tar' \
  --exclude '*.tar.gz' \
  --exclude '*.tar.xz' \
  --include '*/' \
  --include '*.py' \
  --include '*.yml' \
  --include '*.yaml' \
  --include '*.json' \
  --include '*.md' \
  --include 'LICENSE' \
  --include 'benchmark_installs.txt' \
  --exclude '*' \
  "${DCPERF_DIR}/" "${BUILD_CONTEXT}/DCPerf/"

for dir in benchpress packages/tao_bench benchmarks/tao_bench benchmarks/tao_bench_autoscale; do
  mkdir -p "${BUILD_CONTEXT}/DCPerf/$(dirname "${dir}")"
  rsync -a --delete \
    --exclude '.git/' \
    --exclude '__pycache__/' \
    --exclude '.pytest_cache/' \
    --exclude 'benchmark_metrics_*/' \
    --exclude 'results/' \
    --exclude 'logs/' \
    --exclude 'build-folly/' \
    --exclude 'buck-out/' \
    --exclude 'certs/*.key' \
    --exclude '*.log' \
    --exclude 'client_*.log' \
    --exclude 'server*.log' \
    --exclude 'tao-bench-server-*.log' \
    "${DCPERF_DIR}/${dir}/" "${BUILD_CONTEXT}/DCPerf/${dir}/"
done

log "Removing generated metrics/log residue from build context"
find "${BUILD_CONTEXT}/DCPerf" -maxdepth 1 -type d -name 'benchmark_metrics_*' -prune -exec rm -rf {} +
rm -rf "${BUILD_CONTEXT}/DCPerf/results" "${BUILD_CONTEXT}/DCPerf/logs"
find "${BUILD_CONTEXT}/DCPerf" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "${BUILD_CONTEXT}/DCPerf" -type d -name '.pytest_cache' -prune -exec rm -rf {} +
find "${BUILD_CONTEXT}/DCPerf" -type f \( \
  -name '*.log' -o \
  -name 'client_*.log' -o \
  -name 'server*.log' -o \
  -name 'tao-bench-server-*.log' -o \
  -name '*.tar' -o \
  -name '*.tar.gz' -o \
  -name '*.tar.xz' \
\) -delete

if find "${BUILD_CONTEXT}/DCPerf" -maxdepth 1 \( -name 'benchmark_metrics_*' -o -name 'results' -o -name 'logs' \) | grep -q .; then
  die "Build context still contains generated DCPerf output directories"
fi

for lib in /usr/local/lib/libgflags* /usr/local/lib/libglog*; do
  if [[ -e "${lib}" || -L "${lib}" ]]; then
    cp -a "${lib}" "${BUILD_CONTEXT}/host-libs/"
  fi
done

cp "${CBS_ROOT}/containers/Dockerfile.dcperf-taobench" "${BUILD_CONTEXT}/Dockerfile"

log "Build context size:"
du -sh "${BUILD_CONTEXT}/DCPerf" || true

build_args=()
if [[ -n "${APT_MIRROR}" ]]; then
  log "Using apt mirror: ${APT_MIRROR}"
  build_args+=(--build-arg "APT_MIRROR=${APT_MIRROR}")
fi
if [[ -n "${PROXY}" ]]; then
  log "Using build proxy: ${PROXY}"
  build_args+=(--build-arg "http_proxy=${PROXY}")
  build_args+=(--build-arg "https_proxy=${PROXY}")
  build_args+=(--build-arg "HTTP_PROXY=${PROXY}")
  build_args+=(--build-arg "HTTPS_PROXY=${PROXY}")
fi

log "Building image ${IMAGE}"
docker build --network="${DOCKER_BUILD_NETWORK}" "${build_args[@]}" -t "${IMAGE}" "${BUILD_CONTEXT}"

log "Validating image ${IMAGE}"
docker run --rm "${IMAGE}" bash -lc '
set -euo pipefail
cd /workspace/DCPerf
test -x ./benchpress_cli.py
test -d benchmarks/tao_bench
test -d benchmarks/tao_bench_autoscale
test -d packages/tao_bench
test ! -d results
test ! -d logs
if find . -maxdepth 1 \( -name "benchmark_metrics_*" -o -name "*.log" \) | grep -q .; then
  echo "Image contains generated DCPerf output residue" >&2
  find . -maxdepth 1 \( -name "benchmark_metrics_*" -o -name "*.log" \) >&2
  exit 1
fi
openssl version
ldconfig -p | grep -E "libgflags|libssl" >/dev/null
python3 - <<PY
import click
import yaml
import tabulate
import pandas
import numpy
PY
'

log "Image ready: ${IMAGE}"
docker image ls "${IMAGE_NAME}" --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'
