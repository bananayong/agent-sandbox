#!/bin/bash
set -euo pipefail

# ============================================================
# Agent Sandbox - Convenience Runner
# ============================================================

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
  echo "Building agent-sandbox image..."
  docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
}

is_container_running() {
  docker ps -q -f name="^${CONTAINER_NAME}$" | grep -q .
}

stop_container() {
  if is_container_running; then
    echo "Stopping $CONTAINER_NAME..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
  else
    echo "Container $CONTAINER_NAME is not running."
  fi
}

reset_home() {
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

  # Resolve to absolute path
  workspace_dir="$(cd "$workspace_dir" && pwd)"

  # Ensure sandbox home exists
  mkdir -p "$SANDBOX_HOME"

  # Check if image exists
  if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "Image $IMAGE_NAME not found. Building..."
    build_image
  fi

  # Attach to existing container if running
  if is_container_running; then
    echo "Attaching to running container..."
    docker exec -it "$CONTAINER_NAME" /bin/zsh
    return
  fi

  # Remove stopped container with same name
  docker rm "$CONTAINER_NAME" 2>/dev/null || true

  echo "Starting agent sandbox..."
  echo "  Workspace: $workspace_dir"
  echo "  Home:      $SANDBOX_HOME"
  echo ""

  # Build docker run command
  local docker_args=(
    docker run -it
    --name "$CONTAINER_NAME"
    --hostname sandbox
    --security-opt no-new-privileges:true
    --memory 8g
    -v "$workspace_dir:/workspace"
    -v "$SANDBOX_HOME:/home/sandbox"
  )

  # SSH agent forwarding
  if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    docker_args+=(-v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock:ro")
    docker_args+=(-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
  fi

  # Pass API keys if set
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

# Execute actions
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
