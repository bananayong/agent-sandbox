#!/bin/bash
set -euo pipefail

# ============================================================
# Agent Sandbox - Convenience Runner
# ============================================================
# This script is the main entrypoint for local use.
# It does four jobs:
# 1) build image
# 2) run/attach container
# 3) stop container
# 4) reset persisted sandbox home
#
# Important design:
# - Project files are mounted to /workspace
# - Sandbox user home is persisted on host at ~/.agent-sandbox/home
# - Docker socket is forwarded when available for Docker-out-of-Docker (DooD)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="agent-sandbox:latest"
CONTAINER_NAME="agent-sandbox"
SANDBOX_HOME="${HOME}/.agent-sandbox/home"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [WORKSPACE_DIR]

Run the agent sandbox Docker container.

Arguments:
  WORKSPACE_DIR    Directory to mount as /workspace (default: current directory)

Options:
  -b, --build      Build the Docker image before running
  -r, --reset      Reset sandbox home (removes all persisted configs)
  -s, --stop       Stop the running container
  -h, --help       Show this help message

Examples:
  $(basename "$0")                      # Current directory as workspace
  $(basename "$0") ~/projects/myapp     # Specific directory
  $(basename "$0") -b .                 # Build image first, then run
  $(basename "$0") -r                   # Reset all persisted settings
EOF
}

build_image() {
  # Build from the directory where this script lives.
  # This avoids issues when user runs ./run.sh from another path.
  echo "Building agent-sandbox image..."
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
}

is_container_running() {
  # Return success when a container with exact name is running.
  # grep -q . means "any non-empty output exists".
  docker ps -q -f name="^${CONTAINER_NAME}$" | grep -q .
}

stop_container() {
  # Stop and remove only this sandbox container.
  # Other containers are untouched.
  if is_container_running; then
    echo "Stopping $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME"
    # Ignore error if already removed after stop.
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
  else
    echo "Container $CONTAINER_NAME is not running."
  fi
}

reset_home() {
  # Reset means deleting persisted home directory on host.
  # This wipes shell history, agent login state, and dotfiles.
  read -p "This will delete all persisted configs at $SANDBOX_HOME. Continue? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$SANDBOX_HOME"
    echo "Sandbox home reset."
  else
    echo "Cancelled."
  fi
}

run_container() {
  local workspace_dir="$1"

  # Resolve to absolute path so docker -v always receives a stable path.
  workspace_dir="$(cd "$workspace_dir" && pwd)"

  # Ensure persisted home directory exists on host before mounting.
  mkdir -p "$SANDBOX_HOME"

  # Auto-build image if missing (first run convenience).
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Image $IMAGE_NAME not found. Building..."
    build_image
  fi

  # If already running, attach instead of creating another container.
  # This keeps one stable sandbox state and avoids duplicate names.
  if is_container_running; then
    echo "Attaching to running container..."
    docker exec -it "$CONTAINER_NAME" /bin/zsh
    return
  fi

  # If a stopped container with same name exists, remove it first.
  docker rm "$CONTAINER_NAME" 2>/dev/null || true

  echo "Starting agent sandbox..."
  echo "  Workspace: $workspace_dir"
  echo "  Home:      $SANDBOX_HOME"
  echo ""

  # Build docker run command as an array (safe quoting of arguments).
  local docker_args=(
    docker run -it
    --name "$CONTAINER_NAME"
    --hostname sandbox
    # Block privilege escalation inside container.
    # This intentionally makes setuid/sudo elevation unavailable.
    --security-opt no-new-privileges:true
    --memory 8g
    # User project mount.
    -v "$workspace_dir:/workspace"
    # Persisted sandbox home mount.
    -v "$SANDBOX_HOME:/home/sandbox"
  )

  # Docker socket forwarding (DooD):
  # Prefer DOCKER_HOST unix:// socket when configured.
  # Fallback to common local socket paths.
  local docker_sock=""
  if [[ -n "${DOCKER_HOST:-}" && "${DOCKER_HOST}" == unix://* ]]; then
    docker_sock="${DOCKER_HOST#unix://}"
  elif [[ -S /var/run/docker.sock ]]; then
    docker_sock="/var/run/docker.sock"
  elif [[ -S "$HOME/.docker/run/docker.sock" ]]; then
    docker_sock="$HOME/.docker/run/docker.sock"
  fi
  if [[ -n "$docker_sock" ]]; then
    # Mount socket to default in-container path expected by docker CLI.
    docker_args+=(-v "$docker_sock:/var/run/docker.sock")
    # Add socket's group so non-root sandbox user can access docker.
    # Handles both macOS (stat -f) and Linux (stat -c).
    local sock_gid
    sock_gid=$(stat -f '%g' "$docker_sock" 2>/dev/null || stat -c '%g' "$docker_sock" 2>/dev/null)
    if [[ -n "$sock_gid" ]]; then
      docker_args+=(--group-add "$sock_gid")
    fi
  fi

  # Forward SSH agent socket when available.
  # This allows git/ssh auth from inside container without copying keys.
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    docker_args+=(-v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock:ro")
    docker_args+=(-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
  fi

  # Forward selected API tokens only when set on host.
  # Values are not hardcoded in image.
  for key in ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GITHUB_TOKEN OPENCODE_API_KEY; do
    if [[ -n "${!key:-}" ]]; then
      docker_args+=(-e "$key")
    fi
  done

  docker_args+=("$IMAGE_NAME")

  "${docker_args[@]}"
}

# ============================================================
# Parse arguments
# ============================================================
# Flags are parsed manually for portability.
# Default behavior: run current directory as workspace.
DO_BUILD=false
DO_RESET=false
DO_STOP=false
WORKSPACE="."

while [[ $# -gt 0 ]]; do
  case $1 in
    -b|--build)
      DO_BUILD=true
      shift
      ;;
    -r|--reset)
      DO_RESET=true
      shift
      ;;
    -s|--stop)
      DO_STOP=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      WORKSPACE="$1"
      shift
      ;;
  esac
done

# Execute action flags first, then run container flow.
if $DO_RESET; then
  reset_home
  exit 0
fi

if $DO_STOP; then
  stop_container
  exit 0
fi

if $DO_BUILD; then
  build_image
fi

# Validate workspace directory
if [[ ! -d "$WORKSPACE" ]]; then
  echo "Error: Directory '$WORKSPACE' does not exist."
  exit 1
fi

run_container "$WORKSPACE"
