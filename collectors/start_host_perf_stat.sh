#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${1:?Usage: start_host_perf_stat.sh <container> <pid_pattern> <out_file> <pid_file>}"
PID_PATTERN="${2:?Usage: start_host_perf_stat.sh <container> <pid_pattern> <out_file> <pid_file>}"
OUT_FILE="${3:?Usage: start_host_perf_stat.sh <container> <pid_pattern> <out_file> <pid_file>}"
PID_FILE="${4:?Usage: start_host_perf_stat.sh <container> <pid_pattern> <out_file> <pid_file>}"
INTERVAL_MS="${5:-1000}"

mkdir -p "$(dirname "${OUT_FILE}")"
mkdir -p "$(dirname "${PID_FILE}")"

HOST_PID="$(
  docker top "${CONTAINER}" -eo pid,args 2>/dev/null \
    | grep "${PID_PATTERN}" \
    | grep -v grep \
    | awk '{print $1}' \
    | head -n 1 || true
)"

if [ -z "${HOST_PID}" ]; then
  HOST_PID="$(
    ps -e -o pid,args \
      | grep "${PID_PATTERN}" \
      | grep -v grep \
      | awk '{print $1}' \
      | head -n 1 || true
  )"
fi

if [ -z "${HOST_PID}" ]; then
  echo "[ERROR] Cannot find host PID by pattern: ${PID_PATTERN}" >&2
  echo "[DEBUG] docker top ${CONTAINER}:" >&2
  docker top "${CONTAINER}" aux >&2 || true
  echo "[DEBUG] host processes:" >&2
  ps -e -o pid,ppid,stat,comm,args | grep -E 'tao|benchpress|memcached' | grep -v grep >&2 || true
  exit 1
fi

echo "[INFO] host perf target PID=${HOST_PID}, pattern=${PID_PATTERN}" >&2

sudo -n nohup perf stat -p "${HOST_PID}" -I "${INTERVAL_MS}" -x, \
  -e cycles,instructions,branches,branch-misses,cache-references,cache-misses,context-switches,cpu-migrations,page-faults \
  > /tmp/host_perf_stat_stdout.log \
  2> "${OUT_FILE}" &

echo $! > "${PID_FILE}"

echo "[INFO] host perf stat started. collector_pid=$(cat "${PID_FILE}")" >&2
echo "[INFO] perf log: ${OUT_FILE}" >&2