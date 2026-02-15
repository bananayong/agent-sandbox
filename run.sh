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
NETWORK_NAME="agent-sandbox-net"
SANDBOX_HOME="${HOME}/.agent-sandbox/home"

detect_host_docker_socket() {
  # Pick the most likely host Docker socket path.
  # Priority:
  # 1) DOCKER_HOST=unix://...
  # 2) /var/run/docker.sock
  # 3) rootless docker socket (/run/user/<uid>/docker.sock)
  # 4) Docker Desktop user socket (~/.docker/run/docker.sock)
  if [[ -n "${DOCKER_HOST:-}" && "${DOCKER_HOST}" == unix://* ]]; then
    echo "${DOCKER_HOST#unix://}"
    return
  fi
  if [[ -S /var/run/docker.sock ]]; then
    echo "/var/run/docker.sock"
    return
  fi
  local rootless_sock="/run/user/$(id -u)/docker.sock"
  if [[ -S "$rootless_sock" ]]; then
    echo "$rootless_sock"
    return
  fi
  if [[ -S "$HOME/.docker/run/docker.sock" ]]; then
    echo "$HOME/.docker/run/docker.sock"
    return
  fi
}

ensure_host_docker_access() {
  # Fail fast with actionable diagnostics when host docker daemon is
  # unreachable, instead of surfacing opaque "permission denied" later.
  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker CLI is not installed or not in PATH."
    return 1
  fi

  if docker version >/dev/null 2>&1; then
    return 0
  fi

  local sock
  sock="$(detect_host_docker_socket || true)"

  echo "Error: cannot access host Docker daemon."
  if [[ -n "$sock" ]]; then
    echo "  Socket: $sock"
    # Print owner/group/mode to help diagnose permission mismatch quickly.
    local sock_owner sock_group sock_mode
    portable_stat() {
      local darwin_fmt="$1"
      local linux_fmt="$2"
      local target="$3"
      if stat -c "$linux_fmt" "$target" >/dev/null 2>&1; then
        stat -c "$linux_fmt" "$target"
        return
      fi
      if stat -f "$darwin_fmt" "$target" >/dev/null 2>&1; then
        stat -f "$darwin_fmt" "$target"
        return
      fi
      echo "?"
    }
    sock_owner="$(portable_stat '%u' '%u' "$sock")"
    sock_group="$(portable_stat '%g' '%g' "$sock")"
    sock_mode="$(portable_stat '%Sp' '%A' "$sock")"
    echo "  Owner UID: $sock_owner"
    echo "  Group GID: $sock_group"
    echo "  Mode:      $sock_mode"
  else
    echo "  No docker socket found at common paths."
  fi

  echo "Try one of these fixes:"
  local shell_user="${USER:-$(id -un 2>/dev/null || echo '<your-user>')}"
  echo "  1) Linux group fix: sudo usermod -aG docker \"$shell_user\" && newgrp docker"
  echo "  2) Rootless docker: export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock"
  echo "  3) Docker Desktop: ensure Docker app/daemon is running"
  return 1
}

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
  ensure_host_docker_access
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
  ensure_host_docker_access
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

ensure_network() {
  # Ensure a custom bridge network with MTU 1280.
  # Why? Host path MTU can be lower than 1500 (VPN/VM/tunnels), which may
  # break TLS streams and surface as socket/SSL errors in Node-based CLIs.
  local desired_mtu="${AGENT_SANDBOX_NET_MTU:-1280}"
  if [[ ! "$desired_mtu" =~ ^[0-9]+$ ]]; then
    echo "Warning: invalid AGENT_SANDBOX_NET_MTU='$desired_mtu', using 1280"
    desired_mtu="1280"
  fi
  local current_mtu=""
  current_mtu="$(docker network inspect -f '{{index .Options "com.docker.network.driver.mtu"}}' "$NETWORK_NAME" 2>/dev/null || true)"

  if [[ -z "$current_mtu" ]]; then
    echo "Creating Docker network $NETWORK_NAME (MTU ${desired_mtu})..."
    docker network create --driver bridge --opt "com.docker.network.driver.mtu=${desired_mtu}" "$NETWORK_NAME"
    return
  fi

  # Existing networks keep old options. Recreate when MTU differs so fixes
  # apply even for users who created this network before MTU hardening.
  if [[ "$current_mtu" != "$desired_mtu" ]]; then
    echo "Recreating Docker network $NETWORK_NAME (MTU ${current_mtu} -> ${desired_mtu})..."
    docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
    docker network create --driver bridge --opt "com.docker.network.driver.mtu=${desired_mtu}" "$NETWORK_NAME"
  fi
}

run_container() {
  local workspace_dir="$1"
  ensure_host_docker_access

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
    # If running container is attached to a different network, attaching hides
    # stale networking issues. Ask user to recreate container explicitly.
    local running_network
    running_network="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [[ -n "$running_network" && "$running_network" != "$NETWORK_NAME" ]]; then
      echo "Container is running on network '$running_network' (expected '$NETWORK_NAME')."
      echo "Run './run.sh -s' then './run.sh .' to recreate with updated network settings."
      return 1
    fi
    echo "Attaching to running container..."
    docker exec -it "$CONTAINER_NAME" /bin/zsh
    return
  fi

  # If a stopped container with same name exists, remove it first.
  docker rm "$CONTAINER_NAME" 2>/dev/null || true

  # Ensure custom network with safe MTU exists.
  # Do this after removing stale container to avoid "active endpoints" on rm.
  ensure_network

  echo "Starting agent sandbox..."
  echo "  Workspace: $workspace_dir"
  echo "  Home:      $SANDBOX_HOME"
  echo ""

  # Build docker run command as an array (safe quoting of arguments).
  local docker_args=(
    docker run -it
    --name "$CONTAINER_NAME"
    --hostname sandbox
    # Use custom network with safe MTU to prevent SSL/TLS packet corruption.
    --network "$NETWORK_NAME"
    # Block privilege escalation inside container.
    # This intentionally makes setuid/sudo elevation unavailable.
    --security-opt no-new-privileges:true
    --memory 8g
    # User project mount.
    -v "$workspace_dir:/workspace"
    # Persisted sandbox home mount.
    -v "$SANDBOX_HOME:/home/sandbox"
  )

  # Mount a host path into the container at the same absolute path.
  # This is used for trust stores referenced by env vars so Node/OpenSSL can
  # actually read the files from inside the container.
  mount_host_path_ro_if_exists() {
    local host_path="$1"
    if [[ -z "$host_path" ]]; then
      return
    fi
    if [[ ! -e "$host_path" ]]; then
      return
    fi
    # Keep the same path in container to match env var value exactly.
    docker_args+=(-v "$host_path:$host_path:ro")
  }

  # Docker socket forwarding (DooD):
  # Prefer DOCKER_HOST unix:// socket when configured.
  # Fallback to common local socket paths.
  local docker_sock=""
  docker_sock="$(detect_host_docker_socket || true)"
  if [[ -n "$docker_sock" ]]; then
    # Mount socket to default in-container path expected by docker CLI.
    docker_args+=(-v "$docker_sock:/var/run/docker.sock")
    # Add socket's group so non-root sandbox user can access docker.
    # Try Linux stat first (-c), then macOS (-f). Order matters because
    # Linux stat -f means --file-system and pollutes stdout with filesystem
    # info even when it fails, corrupting the captured GID value.
    local sock_gid
    sock_gid=$(stat -c '%g' "$docker_sock" 2>/dev/null || stat -f '%g' "$docker_sock" 2>/dev/null)
    if [[ -n "$sock_gid" ]]; then
      docker_args+=(--group-add "$sock_gid")
    fi

    # Rootless docker sockets are often user-owned (0600). In that case,
    # sandbox UID 1000 may not match host UID and docker access fails.
    # Auto-switch to host UID:GID unless explicitly disabled.
    local host_uid host_gid sock_uid
    host_uid="$(id -u)"
    host_gid="$(id -g)"
    sock_uid="$(stat -c '%u' "$docker_sock" 2>/dev/null || stat -f '%u' "$docker_sock" 2>/dev/null || echo '')"
    local match_host_user="${AGENT_SANDBOX_MATCH_HOST_USER:-auto}"
    if [[ "$match_host_user" == "1" ]] || [[ "$match_host_user" == "auto" && -n "$sock_uid" && "$sock_uid" == "$host_uid" && "$host_uid" != "1000" ]]; then
      echo "Using host UID:GID (${host_uid}:${host_gid}) for docker socket compatibility."
      docker_args+=(--user "${host_uid}:${host_gid}")
      docker_args+=(-e HOME=/home/sandbox)
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

  # Forward common proxy and TLS trust environment variables.
  # This is important in corporate/VPN setups where direct internet is blocked
  # and Node CLIs (claude/codex/gemini) must use proxy/custom CA settings.
  for key in \
    HTTP_PROXY HTTPS_PROXY NO_PROXY \
    http_proxy https_proxy no_proxy \
    ALL_PROXY all_proxy \
    SSL_CERT_FILE SSL_CERT_DIR \
    NODE_EXTRA_CA_CERTS \
    AGENT_SANDBOX_NODE_TLS_COMPAT \
    AGENT_SANDBOX_AUTO_APPROVE \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC \
    DISABLE_ERROR_REPORTING \
    DISABLE_TELEMETRY; do
    if [[ -n "${!key:-}" ]]; then
      docker_args+=(-e "$key")
    fi
  done

  # Default-disable Claude nonessential traffic (telemetry/event export), which
  # is a common failure point on networks that trigger TLS BAD_RECORD_MAC.
  # Users can opt out by explicitly setting CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=0.
  local nonessential_traffic="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
  docker_args+=(-e "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$nonessential_traffic")
  # Keep error reporting off by default for the same network stability reason.
  local disable_error_reporting="${DISABLE_ERROR_REPORTING:-1}"
  docker_args+=(-e "DISABLE_ERROR_REPORTING=$disable_error_reporting")
  # Disable telemetry exports by default (BigQuery/metrics path).
  local disable_telemetry="${DISABLE_TELEMETRY:-1}"
  docker_args+=(-e "DISABLE_TELEMETRY=$disable_telemetry")
  # Default to max-autonomy mode for agent CLIs in the sandbox shell.
  # Set AGENT_SANDBOX_AUTO_APPROVE=0 on host to restore interactive prompts.
  local auto_approve="${AGENT_SANDBOX_AUTO_APPROVE:-1}"
  docker_args+=(-e "AGENT_SANDBOX_AUTO_APPROVE=$auto_approve")

  # Apply Node TLS compatibility defaults at container runtime (no image rebuild
  # required). This protects Node-based CLIs on networks where TLS 1.3 records
  # intermittently fail with BAD_RECORD_MAC, while keeping user overrides.
  local node_options_effective="${NODE_OPTIONS:-}"
  local tls_compat="${AGENT_SANDBOX_NODE_TLS_COMPAT:-1}"
  if [[ "$tls_compat" == "1" ]]; then
    if [[ "$node_options_effective" != *"--tls-max-v1.2"* ]]; then
      node_options_effective="${node_options_effective:+$node_options_effective }--tls-max-v1.2"
    fi
    if [[ "$node_options_effective" != *"--tls-min-v1.2"* ]]; then
      node_options_effective="${node_options_effective:+$node_options_effective }--tls-min-v1.2"
    fi
    if [[ "$node_options_effective" != *"--dns-result-order=ipv4first"* ]]; then
      node_options_effective="${node_options_effective:+$node_options_effective }--dns-result-order=ipv4first"
    fi
  fi
  if [[ -n "$node_options_effective" ]]; then
    docker_args+=(-e "NODE_OPTIONS=$node_options_effective")
  fi

  # If host cert paths are provided, also mount them so they exist inside
  # container. Without this, only env var values are forwarded and TLS clients
  # may fail with SSL/TLS handshake errors.
  mount_host_path_ro_if_exists "${SSL_CERT_FILE:-}"
  mount_host_path_ro_if_exists "${SSL_CERT_DIR:-}"
  mount_host_path_ro_if_exists "${NODE_EXTRA_CA_CERTS:-}"

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
