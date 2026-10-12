#!/usr/bin/env bash

set -euo pipefail

readonly API_CONTAINER="trading-balance-trade-api"
readonly WORKER_CONTAINER="trading-balance-strategy-worker"
readonly IMAGE="trading-balance-trade-api"
readonly MOUNT_TARGET="/var/lib/trading-balance"
readonly API_PORT="127.0.0.1:8000:8000"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"

DOCKERFILE_PATH="${DOCKERFILE_PATH:-backend/Dockerfile}"
API_ENV_FILE="${API_ENV_FILE:-/etc/trading-balance/trade-api.env}"
PERSISTENT_DIR="${PERSISTENT_DIR:-/var/lib/trading-balance}"

resolve_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$REPO_ROOT" "$1" ;;
  esac
}

DOCKERFILE_PATH="$(resolve_path "$DOCKERFILE_PATH")"
API_ENV_FILE="$(resolve_path "$API_ENV_FILE")"
PERSISTENT_DIR="$(resolve_path "$PERSISTENT_DIR")"

usage() {
  cat <<'USAGE'
Usage: ./docker_manage.sh [--api-only] <build|start|stop|restart|rebuild|status|logs|help> [api|worker]

The worker is paused: start, restart, and rebuild stop an existing worker first
and manage only the API; stop handles the worker before the API. No command
starts, restarts, or recreates the worker. Status and logs can still inspect the
retained worker container. The optional api|worker target is accepted only by logs.
--api-only remains accepted as a compatibility alias and enforces the same pause.

Path overrides for local use:
  DOCKERFILE_PATH  Dockerfile path (default: backend/Dockerfile)
  API_ENV_FILE     API env-file path (default: /etc/trading-balance/trade-api.env)
  PERSISTENT_DIR   SQLite bind-mount directory (default: /var/lib/trading-balance)
USAGE
}

fail() {
  printf 'docker_manage.sh: %s\n' "$*" >&2
  return 1
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    fail "Docker CLI is not available in PATH."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon is unavailable or permission was denied."
    return 1
  fi
}

container_state() {
  local name="$1"
  local running

  if running="$(docker inspect --format '{{.State.Running}}' "$name" 2>/dev/null)"; then
    case "$running" in
      true) printf 'running\n' ;;
      false) printf 'stopped\n' ;;
      *) fail "Docker returned an unknown state for container $name." ;;
    esac
  else
    printf 'missing\n'
  fi
}

stop_worker_if_running() {
  local worker_state
  worker_state="$(container_state "$WORKER_CONTAINER")" || return 1
  if [[ "$worker_state" == "running" ]]; then
    docker stop "$WORKER_CONTAINER" || {
      fail "Could not stop the worker container; the API was left untouched."
      return 1
    }
  fi
}

require_file() {
  [[ -f "$2" ]] || fail "Required $1 file is missing: $2"
}

require_directory() {
  [[ -d "$2" ]] || fail "Required $1 directory is missing: $2"
}

require_runtime_paths() {
  require_file "API env" "$API_ENV_FILE" || return 1
  require_directory "persistent data" "$PERSISTENT_DIR" || return 1
}

require_image() {
  docker image inspect "$IMAGE" >/dev/null 2>&1 || fail "Docker image $IMAGE is unavailable; run build first."
}

api_run() {
  docker run --detach \
    --name "$API_CONTAINER" \
    --restart unless-stopped \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --pids-limit=128 \
    --user 10001:10001 \
    --env-file "$API_ENV_FILE" \
    --mount "type=bind,source=$PERSISTENT_DIR,target=$MOUNT_TARGET" \
    -p "$API_PORT" \
    "$IMAGE"
}

show_one_status() {
  local name="$1"
  local state
  state="$(container_state "$name")"
  printf '%s: %s\n' "$name" "$state"
}

report_rebuild_failure() {
  local name
  local state
  printf 'Rebuild recreation failed; current container state:\n' >&2
  for name in "$API_CONTAINER" "$WORKER_CONTAINER"; do
    if state="$(container_state "$name")"; then
      printf '  %s: %s\n' "$name" "$state" >&2
    else
      printf '  %s: unknown\n' "$name" >&2
    fi
  done
  printf 'No automatic rollback was attempted. Use status and the normal operator recovery process.\n' >&2
}

if [[ "${1:-}" == "--api-only" ]]; then
  # Compatibility alias: every lifecycle path now keeps the worker paused.
  shift
fi

if [[ "$#" -lt 1 ]]; then
  usage >&2
  exit 2
fi

COMMAND="$1"
shift
LOG_TARGET="api"

if [[ "$COMMAND" == "logs" ]]; then
  if [[ "$#" -gt 1 ]]; then
    fail "logs accepts at most one target: api or worker." || exit 2
  fi
  if [[ "$#" -eq 1 ]]; then
    LOG_TARGET="$1"
  fi
  case "$LOG_TARGET" in
    api|worker) ;;
    *) fail "logs target must be api or worker." || exit 2 ;;
  esac
elif [[ "$#" -ne 0 ]]; then
  fail "only logs accepts an api or worker target." || exit 2
fi

case "$COMMAND" in
  help)
    usage
    exit 0
    ;;
  build|start|stop|restart|rebuild|status|logs) ;;
  *)
    fail "unknown command: $COMMAND" || exit 2
    ;;
esac

case "$COMMAND" in
  build)
    require_file "Dockerfile" "$DOCKERFILE_PATH" || exit 1
    require_docker || exit 1
    cd -- "$REPO_ROOT"
    docker build -f "$DOCKERFILE_PATH" -t "$IMAGE" .
    ;;

  start)
    require_docker || exit 1
    stop_worker_if_running || exit 1

    API_STATE="$(container_state "$API_CONTAINER")"
    if [[ "$API_STATE" == "missing" ]]; then
      require_runtime_paths || exit 1
      require_image || exit 1
    fi

    if [[ "$API_STATE" == "missing" ]]; then
      api_run || { fail "Could not create the API container."; exit 1; }
    elif [[ "$API_STATE" == "stopped" ]]; then
      docker start "$API_CONTAINER" || { fail "Could not start the API container."; exit 1; }
    fi
    ;;

  stop)
    require_docker || exit 1
    stop_worker_if_running || exit 1
    API_STATE="$(container_state "$API_CONTAINER")"
    if [[ "$API_STATE" == "running" ]]; then
      docker stop "$API_CONTAINER" || { fail "Could not stop the API container."; exit 1; }
    fi
    ;;

  restart)
    require_docker || exit 1
    stop_worker_if_running || exit 1
    API_STATE="$(container_state "$API_CONTAINER")"
    if [[ "$API_STATE" == "missing" ]]; then
      fail "restart requires the API container to exist."
      exit 1
    fi
    docker restart "$API_CONTAINER" || { fail "Could not restart the API container."; exit 1; }
    ;;

  rebuild)
    require_file "Dockerfile" "$DOCKERFILE_PATH" || exit 1
    require_docker || exit 1
    stop_worker_if_running || exit 1
    require_runtime_paths || exit 1

    cd -- "$REPO_ROOT"
    if ! docker build -f "$DOCKERFILE_PATH" -t "$IMAGE" .; then
      fail "Image build failed; the API container was left untouched and the worker remains paused."
      exit 1
    fi

    API_STATE="$(container_state "$API_CONTAINER")"
    if [[ "$API_STATE" == "running" ]]; then
      if ! docker stop "$API_CONTAINER"; then
        fail "Could not stop the API container before replacement."
        report_rebuild_failure
        exit 1
      fi
    fi
    if [[ "$API_STATE" != "missing" ]] && ! docker rm "$API_CONTAINER"; then
      fail "Could not remove the API container before replacement."
      report_rebuild_failure
      exit 1
    fi

    if ! api_run; then
      fail "Could not recreate the API container."
      report_rebuild_failure
      exit 1
    fi
    ;;

  status)
    require_docker || exit 1
    show_one_status "$API_CONTAINER"
    show_one_status "$WORKER_CONTAINER"
    ;;

  logs)
    require_docker || exit 1
    if [[ "$LOG_TARGET" == "api" ]]; then
      LOG_CONTAINER="$API_CONTAINER"
    else
      LOG_CONTAINER="$WORKER_CONTAINER"
    fi
    LOG_STATE="$(container_state "$LOG_CONTAINER")"
    if [[ "$LOG_STATE" == "missing" ]]; then
      fail "Container $LOG_CONTAINER does not exist."
      exit 1
    fi
    docker logs --tail 100 "$LOG_CONTAINER"
    ;;
esac
