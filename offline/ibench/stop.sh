#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/../../conf/env.sh"

echo "[ibench stop] stopping iBench processes in ${OFFLINE_CONTAINER}..."

docker exec "${OFFLINE_CONTAINER}" bash -c "
for f in /tmp/ibench_*_worker_*.pid /tmp/ibench_memcap.pid; do
  [ -f \"\$f\" ] || continue
  pid=\"\$(cat \"\$f\" 2>/dev/null || true)\"
  [ -n \"\$pid\" ] && kill -TERM \"\$pid\" 2>/dev/null || true
done
sleep 1

pkill -TERM -f '/workspace/iBench/src/cpu' 2>/dev/null || true
pkill -TERM -f '/workspace/iBench/src/memBw' 2>/dev/null || true
pkill -TERM -f '/workspace/iBench/src/memCap' 2>/dev/null || true
pkill -TERM -f '/workspace/iBench/src/l3' 2>/dev/null || true
pkill -TERM -f 'while true; do.*src/cpu' 2>/dev/null || true
pkill -TERM -f 'while true; do.*src/memBw' 2>/dev/null || true
pkill -TERM -f 'while true; do.*src/memCap' 2>/dev/null || true
pkill -TERM -f 'while true; do.*src/l3' 2>/dev/null || true
pkill -TERM -f 'memCap' 2>/dev/null || true
pkill -TERM -f 'memBw' 2>/dev/null || true
sleep 2

for f in /tmp/ibench_*_worker_*.pid /tmp/ibench_memcap.pid; do
  [ -f \"\$f\" ] || continue
  pid=\"\$(cat \"\$f\" 2>/dev/null || true)\"
  [ -n \"\$pid\" ] && kill -KILL \"\$pid\" 2>/dev/null || true
  rm -f \"\$f\"
done

pkill -KILL -f '/workspace/iBench/src/cpu' 2>/dev/null || true
pkill -KILL -f '/workspace/iBench/src/memBw' 2>/dev/null || true
pkill -KILL -f '/workspace/iBench/src/memCap' 2>/dev/null || true
pkill -KILL -f '/workspace/iBench/src/l3' 2>/dev/null || true
pkill -KILL -f 'while true; do.*src/cpu' 2>/dev/null || true
pkill -KILL -f 'while true; do.*src/memBw' 2>/dev/null || true
pkill -KILL -f 'while true; do.*src/memCap' 2>/dev/null || true
pkill -KILL -f 'while true; do.*src/l3' 2>/dev/null || true
pkill -KILL -f 'memCap' 2>/dev/null || true
pkill -KILL -f 'memBw' 2>/dev/null || true
" 2>/dev/null || true

echo "[ibench stop] remaining iBench-related processes:"
docker exec "${OFFLINE_CONTAINER}" bash -c "
ps -ef | grep -E 'memCap|memBw|/workspace/iBench/src/cpu|/workspace/iBench/src/memBw|/workspace/iBench/src/l3|iBench' | grep -v grep || true
" 2>/dev/null || true

echo "[ibench stop] done."
