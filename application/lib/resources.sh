#!/usr/bin/env bash
set -euo pipefail

apply_rdt_hooks() {
  if [[ "${RDT_ENABLE:-0}" != "1" ]]; then
    log "RDT_ENABLE=0, skipping Intel RDT CAT/LLC hooks."
    return 0
  fi

  log "RDT requested. SERVER_LLC_MASK=${SERVER_LLC_MASK:-}, LOADGEN_LLC_MASK=${LOADGEN_LLC_MASK:-}, OFFLINE_LLC_MASK=${OFFLINE_LLC_MASK:-}"
  if command -v pqos >/dev/null 2>&1; then
    log "pqos is available; hook point ready. Apply policy here after container PIDs are known."
  elif [[ -d /sys/fs/resctrl ]]; then
    log "resctrl is mounted; hook point ready. Apply schemata/tasks here after container PIDs are known."
  else
    log "No pqos or /sys/fs/resctrl found; RDT hook cannot be applied on this host."
  fi
}

apply_mba_hooks() {
  if [[ "${MBA_ENABLE:-0}" != "1" ]]; then
    log "MBA_ENABLE=0, skipping Intel MBA hooks."
    return 0
  fi
  log "MBA requested. SERVER_MBA_PERCENT=${SERVER_MBA_PERCENT:-}, LOADGEN_MBA_PERCENT=${LOADGEN_MBA_PERCENT:-}, OFFLINE_MBA_PERCENT=${OFFLINE_MBA_PERCENT:-}"
  log "MBA hook is reserved; use pqos/resctrl schemata once class-of-service policy is selected."
}

apply_network_hooks() {
  if [[ "${NET_SHAPE_ENABLE:-0}" != "1" ]]; then
    log "NET_SHAPE_ENABLE=0, skipping network shaping hooks."
    return 0
  fi
  log "Network shaping requested. NET_IFACE=${NET_IFACE:-}, LOADGEN_NET_RATE=${LOADGEN_NET_RATE:-}, OFFLINE_NET_RATE=${OFFLINE_NET_RATE:-}"
  log "Network hook is reserved; expected implementation uses tc qdisc/class/filter."
}

apply_cpu_frequency_hooks() {
  if [[ "${CPU_FREQ_ENABLE:-0}" != "1" ]]; then
    log "CPU_FREQ_ENABLE=0, skipping CPU frequency hooks."
    return 0
  fi
  log "CPU frequency requested. governor=${CPU_FREQ_GOVERNOR:-}, min=${CPU_FREQ_MIN:-}, max=${CPU_FREQ_MAX:-}"
  if ! command -v cpupower >/dev/null 2>&1; then
    log "cpupower not found; cannot apply CPU frequency policy."
    return 0
  fi
  [[ -n "${CPU_FREQ_GOVERNOR:-}" ]] && app_run sudo -n cpupower frequency-set -g "${CPU_FREQ_GOVERNOR}" || true
  [[ -n "${CPU_FREQ_MIN:-}" ]] && app_run sudo -n cpupower frequency-set -d "${CPU_FREQ_MIN}" || true
  [[ -n "${CPU_FREQ_MAX:-}" ]] && app_run sudo -n cpupower frequency-set -u "${CPU_FREQ_MAX}" || true
}

apply_resource_hooks_before_run() {
  apply_cpu_frequency_hooks
  apply_network_hooks
}

apply_resource_hooks_after_containers() {
  apply_rdt_hooks
  apply_mba_hooks
}

