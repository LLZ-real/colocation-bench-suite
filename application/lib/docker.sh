#!/usr/bin/env bash
set -euo pipefail

docker_resource_args() {
  local role="$1"
  local prefix
  prefix="$(printf '%s' "${role}" | tr '[:lower:]' '[:upper:]')"
  local cgroup_mode="${CGROUP_MODE:-docker}"

  local cgroup_parent="${prefix}_CGROUP_PARENT"
  local cpu_shares="${prefix}_CPU_SHARES"
  local cpu_quota="${prefix}_CPU_QUOTA"
  local cpu_period="${prefix}_CPU_PERIOD"
  local memory_limit="${prefix}_MEMORY_LIMIT"
  local memory_swap="${prefix}_MEMORY_SWAP"
  local blkio_weight="${prefix}_BLKIO_WEIGHT"
  local dev_read_bps="${prefix}_DEVICE_READ_BPS"
  local dev_write_bps="${prefix}_DEVICE_WRITE_BPS"

  DOCKER_RESOURCE_ARGS=()
  case "${cgroup_mode}" in
    docker|systemd)
      [[ -n "${!cgroup_parent:-}" ]] && DOCKER_RESOURCE_ARGS+=(--cgroup-parent "${!cgroup_parent}")
      ;;
    none)
      ;;
    *)
      die "Unknown CGROUP_MODE=${cgroup_mode}; expected docker, systemd, or none"
      ;;
  esac
  [[ -n "${!cpu_shares:-}" ]] && DOCKER_RESOURCE_ARGS+=(--cpu-shares "${!cpu_shares}")
  [[ -n "${!cpu_quota:-}" ]] && DOCKER_RESOURCE_ARGS+=(--cpu-quota "${!cpu_quota}")
  [[ -n "${!cpu_period:-}" ]] && DOCKER_RESOURCE_ARGS+=(--cpu-period "${!cpu_period}")
  [[ -n "${!memory_limit:-}" ]] && DOCKER_RESOURCE_ARGS+=(--memory "${!memory_limit}")
  [[ -n "${!memory_swap:-}" ]] && DOCKER_RESOURCE_ARGS+=(--memory-swap "${!memory_swap}")
  [[ -n "${!blkio_weight:-}" ]] && DOCKER_RESOURCE_ARGS+=(--blkio-weight "${!blkio_weight}")
  [[ -n "${!dev_read_bps:-}" ]] && DOCKER_RESOURCE_ARGS+=(--device-read-bps "${!dev_read_bps}")
  [[ -n "${!dev_write_bps:-}" ]] && DOCKER_RESOURCE_ARGS+=(--device-write-bps "${!dev_write_bps}")
  return 0
}

create_app_container() {
  local role="$1"
  local name="$2"
  local cpuset="$3"
  local mems="$4"
  shift 4
  local volume_args=("$@")
  local DOCKER_RESOURCE_ARGS=()
  docker_resource_args "${role}"

  log "Removing old ${name} if exists..."
  if [[ "${DRY_RUN}" = "1" ]]; then
    app_run docker rm -f "${name}"
  else
    docker rm -f "${name}" >/dev/null 2>&1 || true
  fi

  local cmd=(
    docker run -d --init --name "${name}"
    --network "${APP_DOCKER_NETWORK:-host}"
    --privileged
    --cpuset-cpus "${cpuset}"
    --cpuset-mems "${mems}"
  )

  for v in "${volume_args[@]}"; do
    cmd+=(-v "${v}")
  done

  cmd+=("${DOCKER_RESOURCE_ARGS[@]}")
  cmd+=("${CLAB_IMAGE}" sleep infinity)
  app_run "${cmd[@]}"

  log "${name} created for role=${role}, cpuset=${cpuset}, mems=${mems}"
}

inspect_app_container() {
  local name="$1"
  local out_file="$2"
  if [[ "${DRY_RUN}" = "1" ]]; then
    log "Skipping docker inspect in dry-run: ${name}"
    return 0
  fi
  docker inspect "${name}" > "${out_file}" 2>/dev/null || true
}
