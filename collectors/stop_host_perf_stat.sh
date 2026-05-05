#!/usr/bin/env bash
set -euo pipefail

PID_FILE="${1:?Usage: stop_host_perf_stat.sh <pid_file>}"

if [ -f "${PID_FILE}" ]; then
  PID="$(cat "${PID_FILE}")"

  sudo kill -INT "${PID}" 2>/dev/null || true
  sleep 2
  sudo kill -9 "${PID}" 2>/dev/null || true

  rm -f "${PID_FILE}"
fi
