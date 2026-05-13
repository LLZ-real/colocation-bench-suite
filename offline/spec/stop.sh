#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"

echo "[spec stop] stopping SPEC CPU processes in ${OFFLINE_CONTAINER}..."

docker exec "${OFFLINE_CONTAINER}" bash -c "
pkill -TERM -f 'runcpu' 2>/dev/null || true
pkill -TERM -f 'specrun' 2>/dev/null || true
pkill -TERM -f 'mcf' 2>/dev/null || true
pkill -TERM -f 'lbm' 2>/dev/null || true
pkill -TERM -f 'xz' 2>/dev/null || true
pkill -TERM -f 'omnetpp' 2>/dev/null || true
pkill -TERM -f 'xalancbmk' 2>/dev/null || true
sleep 2
pkill -KILL -f 'runcpu' 2>/dev/null || true
pkill -KILL -f 'specrun' 2>/dev/null || true
pkill -KILL -f 'mcf' 2>/dev/null || true
pkill -KILL -f 'lbm' 2>/dev/null || true
pkill -KILL -f 'xz' 2>/dev/null || true
pkill -KILL -f 'omnetpp' 2>/dev/null || true
pkill -KILL -f 'xalancbmk' 2>/dev/null || true
" 2>/dev/null || true

echo "[spec stop] remaining SPEC-related processes:"
docker exec "${OFFLINE_CONTAINER}" bash -c "
ps -ef | grep -E 'runcpu|specrun|mcf|lbm|xz|omnetpp|xalancbmk' | grep -v grep || true
" 2>/dev/null || true

echo "[spec stop] done."
