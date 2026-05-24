#!/usr/bin/env bash
set -euo pipefail

PATTERN="${1:?Usage: $0 RUN_DIR_PATTERN TAG [DURATION]}"
TAG="${2:?Usage: $0 RUN_DIR_PATTERN TAG [DURATION]}"
DURATION="${3:-300}"

ROOT="/home/lilinzhen/colocate_lab/results/cbs"
CBS_ROOT="/home/lilinzhen/colocation-bench-suite"

KEEPALIVE_PID=""

cleanup() {
  if [ -n "${KEEPALIVE_PID}" ]; then
    kill "${KEEPALIVE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "[watch] pattern=${PATTERN}"
echo "[watch] tag=${TAG}"
echo "[watch] duration=${DURATION}"

echo "[watch] acquiring sudo credential now..."
sudo -v

(
  while true; do
    sudo -n true 2>/dev/null || exit
    sleep 60
  done
) &
KEEPALIVE_PID=$!

RUN_DIR=""

echo "[watch] waiting for run directory..."
while true; do
  RUN_DIR="$(ls -td "${ROOT}"/*"${PATTERN}"* 2>/dev/null | head -n 1 || true)"
  if [ -n "${RUN_DIR}" ]; then
    echo "[watch] found RUN_DIR=${RUN_DIR}"
    break
  fi
  sleep 5
done

echo "[watch] waiting for measured TaoBench client stage..."

while true; do
  if ls "${RUN_DIR}"/raw/client_measured_clients_*.log >/dev/null 2>&1; then
    echo "[watch] detected measured client log"
    break
  fi

  if [ -f "${RUN_DIR}/summary.csv" ]; then
    echo "[watch] summary.csv already exists; experiment may have finished."
    break
  fi

  sudo -n true 2>/dev/null || {
    echo "[ERROR] sudo credential expired before measured stage." >&2
    echo "[HINT] rerun: sudo -v && bash tools/watch_and_perf.sh ${PATTERN} ${TAG} ${DURATION}" >&2
    exit 1
  }

  sleep 3
done

echo "[watch] starting perf attach..."
bash "${CBS_ROOT}/tools/perf_attach_server.sh" "${RUN_DIR}" "${DURATION}" "${TAG}"

echo "[watch] parsing perf result..."
python3 "${CBS_ROOT}/tools/parse_perf_stat.py" "${RUN_DIR}/logs/perf_stat_${TAG}.csv"

echo "[watch] done"
