#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="${1:?Usage: $0 RUN_DIR [duration_sec] [tag]}"
DURATION="${2:-300}"
TAG="${3:-server}"

mkdir -p "${RUN_DIR}/logs"

OUT="${RUN_DIR}/logs/perf_stat_${TAG}.csv"

if ! docker ps --format '{{.Names}}' | grep -qx 'clab-server'; then
  echo "[ERROR] clab-server is not running" >&2
  exit 1
fi

PIDS="$(docker top clab-server -eo pid | awk 'NR>1 {print $1}' | paste -sd, -)"

if [ -z "${PIDS}" ]; then
  echo "[ERROR] failed to get clab-server PIDs" >&2
  exit 1
fi

EVENTS="cycles,instructions,cache-references,cache-misses,LLC-loads,LLC-load-misses,branches,branch-misses,context-switches,cpu-migrations,page-faults"

echo "[INFO] RUN_DIR=${RUN_DIR}"
echo "[INFO] DURATION=${DURATION}"
echo "[INFO] TAG=${TAG}"
echo "[INFO] PIDS=${PIDS}"
echo "[INFO] OUT=${OUT}"
echo "[INFO] EVENTS=${EVENTS}"

sudo -n perf stat \
  -x, \
  -o "${OUT}" \
  -e "${EVENTS}" \
  -p "${PIDS}" \
  -- sleep "${DURATION}"

echo "[OK] wrote ${OUT}"
