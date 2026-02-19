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
# - Sandbox user home is persisted on host at ~/.agent-sandbox/.../home
# - Docker socket is forwarded when available for Docker-out-of-Docker (DooD)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="agent-sandbox:latest"
DEFAULT_CONTAINER_NAME="agent-sandbox"
CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
NETWORK_NAME="agent-sandbox-net"
SANDBOX_ROOT_DIR="${HOME}/.agent-sandbox"
SANDBOX_HOME_OVERRIDE=""
SANDBOX_HOME=""

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
  local rootless_sock
  rootless_sock="/run/user/$(id -u)/docker.sock"
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
  -n, --name NAME  Container name (default: $DEFAULT_CONTAINER_NAME)
      --home DIR    Host directory to mount as /home/sandbox
      --dns LIST    Override container DNS servers (comma/space separated)
  -r, --reset      Reset sandbox home (removes all persisted configs)
  -s, --stop       Stop the running container
  -h, --help       Show this help message

Examples:
  $(basename "$0")                      # Current directory as workspace
  $(basename "$0") ~/projects/myapp     # Specific directory
  $(basename "$0") -b .                 # Build image first, then run
  $(basename "$0") -n codex .           # Custom container + isolated home
  $(basename "$0") --home ~/.agent-sandbox/teamA/home .
  $(basename "$0") --dns "10.0.0.2,1.1.1.1" .
  $(basename "$0") -r                   # Reset all persisted settings

Environment:
  AGENT_SANDBOX_DNS_SERVERS   DNS servers for container (comma/space separated)
  AGENT_SANDBOX_JDTLS_BASE_URLS  Ordered jdtls base URLs for mirror/CDN override
EOF
}

is_valid_container_name() {
  local name="$1"
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
}

resolve_host_path() {
  local path_input="$1"
  if [[ "$path_input" == "~" ]]; then
    path_input="$HOME"
  elif [[ "$path_input" == \~/* ]]; then
    path_input="${HOME}/${path_input#~/}"
  fi
  if [[ "$path_input" != /* ]]; then
    path_input="$PWD/$path_input"
  fi

  # Normalize parent directory when it already exists (keeps behavior for
  # non-existing leaf paths while removing visual noise like "/./").
  local parent_dir base_name
  parent_dir="$(dirname "$path_input")"
  base_name="$(basename "$path_input")"
  if [[ -d "$parent_dir" ]]; then
    path_input="$(cd "$parent_dir" && pwd)/$base_name"
  fi
  # String-level cleanup for visual noise when leaf path doesn't exist yet.
  path_input="${path_input//\/.\//\/}"

  printf '%s\n' "$path_input"
}

default_home_for_container() {
  local container_name="$1"
  # Keep backward compatibility for the default container path.
  if [[ "$container_name" == "$DEFAULT_CONTAINER_NAME" ]]; then
    printf '%s\n' "${SANDBOX_ROOT_DIR}/home"
    return
  fi
  printf '%s\n' "${SANDBOX_ROOT_DIR}/${container_name}/home"
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
  docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
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
  read -r -p "This will delete persisted home for '$CONTAINER_NAME' at $SANDBOX_HOME. Continue? [y/N] " confirm
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

collect_nonloopback_nameservers_from_file() {
  local resolv_file="$1"
  if [[ ! -r "$resolv_file" ]]; then
    return
  fi
  # Skip loopback resolvers because they usually point to host-local stubs
  # (for example 127.0.0.53) that are unreachable from inside containers.
  # Keep IPv4 DNS only because container runtime disables IPv6 by default.
  awk '/^nameserver[[:space:]]+/ {print $2}' "$resolv_file" \
    | awk '$1 !~ /^127\./ && $1 != "::1" && $1 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/ {print $1}'
}

detect_dns_servers() {
  # Priority:
  # 1) explicit AGENT_SANDBOX_DNS_SERVERS (user override)
  # 2) host /etc/resolv.conf non-loopback nameservers
  # 3) systemd-resolved upstream list (/run/systemd/resolve/resolv.conf)
  #
  # Note: container runtime disables IPv6 by default, so only IPv4 resolvers
  # are selected to keep DNS behavior consistent.
  local explicit_dns="${AGENT_SANDBOX_DNS_SERVERS:-}"
  local token
  if [[ -n "$explicit_dns" ]]; then
    local explicit_ipv4_dns
    explicit_ipv4_dns="$(
      for token in ${explicit_dns//,/ }; do
        if [[ "$token" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          printf '%s\n' "$token"
        fi
      done | awk '!seen[$0]++'
    )"
    if [[ -n "$explicit_ipv4_dns" ]]; then
      printf '%s\n' "$explicit_ipv4_dns"
      return
    fi
    echo "Warning: AGENT_SANDBOX_DNS_SERVERS has no valid IPv4 entries; falling back to host DNS." >&2
  fi

  local host_dns
  host_dns="$(collect_nonloopback_nameservers_from_file /etc/resolv.conf | awk '!seen[$0]++')"
  if [[ -n "$host_dns" ]]; then
    printf '%s\n' "$host_dns"
    return
  fi

  collect_nonloopback_nameservers_from_file /run/systemd/resolve/resolv.conf | awk '!seen[$0]++'
}

docker_supports_host_gateway() {
  # host-gateway requires Docker Engine 20.10+.
  local version_raw
  version_raw="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  if [[ -z "$version_raw" ]]; then
    return 1
  fi

  local major minor
  major="$(printf '%s' "$version_raw" | awk -F'[.-]' '{print $1}')"
  minor="$(printf '%s' "$version_raw" | awk -F'[.-]' '{print $2}')"
  if [[ ! "$major" =~ ^[0-9]+$ ]] || [[ ! "$minor" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( major > 20 )) || (( major == 20 && minor >= 10 )); then
    return 0
  fi
  return 1
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
      echo "Run './run.sh -s -n $CONTAINER_NAME' and rerun with the same --name value."
      return 1
    fi
    echo "Attaching to running container..."
    # Prefer attaching to the tmux session started by start.sh.
    # Falls back to plain zsh if tmux session doesn't exist.
    docker exec -it "$CONTAINER_NAME" tmux attach -t main 2>/dev/null \
      || docker exec -it "$CONTAINER_NAME" /bin/zsh
    return
  fi

  # If a stopped container with same name exists, remove it first.
  docker rm "$CONTAINER_NAME" 2>/dev/null || true

  # Ensure custom network with safe MTU exists.
  # Do this after removing stale container to avoid "active endpoints" on rm.
  ensure_network

  echo "Starting agent sandbox..."
  echo "  Container: $CONTAINER_NAME"
  echo "  Workspace: $workspace_dir"
  echo "  Home:      $SANDBOX_HOME"

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

  # Add host.docker.internal mapping for local host service access from
  # inside container (MCP/local tooling).
  if docker_supports_host_gateway; then
    docker_args+=(--add-host host.docker.internal:host-gateway)
    echo "  Host map:  host.docker.internal -> host-gateway"
  else
    echo "  Host map:  skipped (Docker < 20.10)"
  fi

  # Disable IPv6 inside the container network namespace by default.
  # This reduces IPv6-first connection stalls in some Docker/WSL/VPN setups.
  docker_args+=(--sysctl net.ipv6.conf.all.disable_ipv6=1)
  docker_args+=(--sysctl net.ipv6.conf.default.disable_ipv6=1)
  echo "  IPv6:      disabled"

  # Explicitly pass DNS servers when available. This avoids Docker's fallback
  # to public DNS in environments where host resolvers are stub/local only.
  local dns_servers=()
  local dns_server
  while IFS= read -r dns_server; do
    [[ -n "$dns_server" ]] && dns_servers+=("$dns_server")
  done < <(detect_dns_servers)
  if [[ ${#dns_servers[@]} -gt 0 ]]; then
    echo "  DNS:       ${dns_servers[*]}"
    for dns_server in "${dns_servers[@]}"; do
      docker_args+=(--dns "$dns_server")
    done
  else
    echo "  DNS:       docker default (no explicit override)"
  fi

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
    NODE_EXTRA_CA_CERTS; do
    if [[ -n "${!key:-}" ]]; then
      docker_args+=(-e "$key")
    fi
  done

  # Forward optional startup tuning knobs used by entrypoint onboarding.
  for key in AGENT_SANDBOX_JDTLS_BASE_URLS; do
    if [[ -n "${!key:-}" ]]; then
      docker_args+=(-e "$key")
    fi
  done

  # Default-disable Claude nonessential traffic (telemetry/event export), which
  # is a common failure point on networks that trigger TLS BAD_RECORD_MAC.
  docker_args+=(-e "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1")
  # Keep error reporting off by default for the same network stability reason.
  docker_args+=(-e "DISABLE_ERROR_REPORTING=1")
  # Disable telemetry exports by default (BigQuery/metrics path).
  docker_args+=(-e "DISABLE_TELEMETRY=1")
  # Disable background auto-update checks to reduce nonessential calls.
  docker_args+=(-e "DISABLE_AUTOUPDATER=1")

  # Apply Node TLS compatibility defaults at container runtime (no image rebuild
  # required). This protects Node-based CLIs on networks where TLS 1.3 records
  # intermittently fail with BAD_RECORD_MAC.
  local node_options_effective="${NODE_OPTIONS:-}"
  if [[ "$node_options_effective" != *"--tls-max-v1.2"* ]]; then
    node_options_effective="${node_options_effective:+$node_options_effective }--tls-max-v1.2"
  fi
  if [[ "$node_options_effective" != *"--tls-min-v1.2"* ]]; then
    node_options_effective="${node_options_effective:+$node_options_effective }--tls-min-v1.2"
  fi
  if [[ "$node_options_effective" != *"--dns-result-order=ipv4first"* ]]; then
    node_options_effective="${node_options_effective:+$node_options_effective }--dns-result-order=ipv4first"
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

  echo ""
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
DNS_OVERRIDE=""
WORKSPACE="."

while [[ $# -gt 0 ]]; do
  case $1 in
    -b|--build)
      DO_BUILD=true
      shift
      ;;
    -n|--name)
      if [[ $# -lt 2 ]]; then
        echo "Error: --name requires a value (example: --name codex)"
        exit 1
      fi
      CONTAINER_NAME="$2"
      shift 2
      ;;
    --home)
      if [[ $# -lt 2 ]]; then
        echo "Error: --home requires a directory path."
        exit 1
      fi
      SANDBOX_HOME_OVERRIDE="$2"
      shift 2
      ;;
    -r|--reset)
      DO_RESET=true
      shift
      ;;
    -s|--stop)
      DO_STOP=true
      shift
      ;;
    --dns)
      if [[ $# -lt 2 ]]; then
        echo "Error: --dns requires a value (example: --dns \"10.0.0.2,1.1.1.1\")"
        exit 1
      fi
      DNS_OVERRIDE="$2"
      shift 2
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

if ! is_valid_container_name "$CONTAINER_NAME"; then
  echo "Error: invalid container name '$CONTAINER_NAME'."
  echo "Allowed characters: letters, numbers, dot(.), underscore(_), hyphen(-)."
  exit 1
fi

if [[ -n "$SANDBOX_HOME_OVERRIDE" ]]; then
  SANDBOX_HOME="$(resolve_host_path "$SANDBOX_HOME_OVERRIDE")"
else
  SANDBOX_HOME="$(default_home_for_container "$CONTAINER_NAME")"
fi

# Execute action flags first, then run container flow.
# Compare explicit string values instead of executing variable contents.
if [[ "$DO_RESET" == true ]]; then
  reset_home
  exit 0
fi

if [[ "$DO_STOP" == true ]]; then
  stop_container
  exit 0
fi

if [[ "$DO_BUILD" == true ]]; then
  build_image
fi

if [[ -n "$DNS_OVERRIDE" ]]; then
  AGENT_SANDBOX_DNS_SERVERS="$DNS_OVERRIDE"
fi

# Validate workspace directory
if [[ ! -d "$WORKSPACE" ]]; then
  echo "Error: Directory '$WORKSPACE' does not exist."
  exit 1
fi

run_container "$WORKSPACE"
