#!/usr/bin/env bash
set -euo pipefail

# Build and push Docker image to Docker Hub.
# 构建并推送 Docker 镜像到 Docker Hub。

SCRIPT_NAME="$(basename "$0")"
DEFAULT_IMAGE="whalefell/tproxy-transparent-proxy"
IMAGE_NAME="${IMAGE_NAME:-$DEFAULT_IMAGE}"
TAG=""

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --tag <tag> [--image <dockerhub_repo>]

Options:
  --tag     Required. Build and push both 'latest' and this tag.
  --image   Optional. Docker Hub image repo (default: ${DEFAULT_IMAGE}).
  -h, --help

Auth:
  1) Reuse current 'docker login' session if already logged in.
  2) Auto login from .env (DOCKER_USERNAME / DOCKER_TOKEN), if present.
  3) Fallback to DOCKERHUB_USERNAME / DOCKERHUB_TOKEN.
  4) Fallback to interactive docker login prompt.

Examples:
  $SCRIPT_NAME --tag v1.0.0
  $SCRIPT_NAME --tag 2026.02.27 --image yourname/tproxy-transparent-proxy
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' command not found." >&2
    exit 1
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --tag)
        [ "$#" -ge 2 ] || { echo "Error: --tag requires a value." >&2; exit 1; }
        TAG="$2"
        shift 2
        ;;
      --image)
        [ "$#" -ge 2 ] || { echo "Error: --image requires a value." >&2; exit 1; }
        IMAGE_NAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Error: unknown argument '$1'." >&2
        usage
        exit 1
        ;;
    esac
  done

  if [ -z "$TAG" ]; then
    echo "Error: --tag is required." >&2
    usage
    exit 1
  fi
}

ensure_docker_ready() {
  # Validate Docker CLI and daemon availability.
  # 校验 Docker CLI 与守护进程是否可用。
  require_cmd docker
  if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon is not reachable. Please start Docker first." >&2
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "Error: 'docker compose' is not available." >&2
    exit 1
  fi
}

ensure_docker_login() {
  # Reuse existing login; otherwise login via env token or interactive prompt.
  # 优先复用已登录状态；否则使用环境变量令牌或交互方式登录。
  local current_user=""
  current_user="$(docker info --format '{{.Username}}' 2>/dev/null || true)"

  if [ -n "$current_user" ]; then
    log "Docker Hub already logged in as: $current_user"
    return 0
  fi

  load_dotenv_credentials

  log "Docker Hub login required."
  if [ -n "${DOCKER_USERNAME:-}" ] && [ -n "${DOCKER_TOKEN:-}" ]; then
    printf '%s' "${DOCKER_TOKEN}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
  elif [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    printf '%s' "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin
  else
    local login_user=""
    read -r -p "Docker Hub username: " login_user
    if [ -z "$login_user" ]; then
      echo "Error: Docker Hub username cannot be empty." >&2
      exit 1
    fi
    docker login -u "$login_user"
  fi
}

load_dotenv_credentials() {
  # Load DOCKER_USERNAME / DOCKER_TOKEN from local .env if present.
  # 如存在本地 .env，则读取 DOCKER_USERNAME / DOCKER_TOKEN。
  if [ ! -f ".env" ]; then
    return 0
  fi

  if [ -z "${DOCKER_USERNAME:-}" ]; then
    DOCKER_USERNAME="$(sed -n 's/^[[:space:]]*DOCKER_USERNAME[[:space:]]*=[[:space:]]*//p' .env | tail -n1 | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")"
    export DOCKER_USERNAME
  fi

  if [ -z "${DOCKER_TOKEN:-}" ]; then
    DOCKER_TOKEN="$(sed -n 's/^[[:space:]]*DOCKER_TOKEN[[:space:]]*=[[:space:]]*//p' .env | tail -n1 | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")"
    export DOCKER_TOKEN
  fi
}

build_and_push() {
  local latest_ref="${IMAGE_NAME}:latest"
  local tag_ref="${IMAGE_NAME}:${TAG}"

  log "Building image with docker compose (service: mihomo)"
  docker compose build --pull mihomo

  log "Tagging image: ${latest_ref} -> ${tag_ref}"
  docker tag "${latest_ref}" "${tag_ref}"

  log "Pushing image: ${latest_ref}"
  docker push "${latest_ref}"

  log "Pushing image: ${tag_ref}"
  docker push "${tag_ref}"

  log "Done. Published: ${latest_ref}, ${tag_ref}"
}

main() {
  parse_args "$@"
  ensure_docker_ready
  ensure_docker_login
  build_and_push
}

main "$@"
