#!/bin/bash
set -euo pipefail

# Print tool availability for coding agents inside agent-sandbox.
# Usage:
#   agent-tools
#   agent-tools --agent codex
#   agent-tools --agent claude
#   agent-tools --agent gemini

usage() {
  cat <<'EOF'
Usage: agent-tools [--agent codex|claude|gemini|all]

Show tools available to coding agents in this container, including:
- agent CLI command
- managed settings/skills paths
- detected LSP commands from agent settings
- common runtime tool availability
EOF
}

agent_scope="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      if [[ $# -lt 2 ]]; then
        echo "Error: --agent requires one value." >&2
        exit 1
      fi
      agent_scope="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$agent_scope" != "all" && "$agent_scope" != "codex" && "$agent_scope" != "claude" && "$agent_scope" != "gemini" ]]; then
  echo "Error: --agent must be one of codex|claude|gemini|all" >&2
  exit 1
fi

home_dir="${HOME:-/home/sandbox}"

print_lsp_commands() {
  local settings_path="$1"
  if [[ ! -f "$settings_path" ]] || ! command -v jq >/dev/null 2>&1; then
    echo "    - (none)"
    return
  fi

  local lsp_entries=""
  lsp_entries="$(jq -r '
    .lsp // {} | to_entries[]
    | "\(.key): \(.value.command // "missing-command")"
  ' "$settings_path" 2>/dev/null || true)"

  if [[ -z "$lsp_entries" ]]; then
    echo "    - (none)"
    return
  fi

  while IFS= read -r entry; do
    [[ -n "$entry" ]] && echo "    - $entry"
  done <<< "$lsp_entries"
}

print_agent_block() {
  local agent="$1"
  local command_name="$2"
  local settings_path="$3"
  local skills_path="$4"

  local command_state="missing"
  if command -v "$command_name" >/dev/null 2>&1; then
    command_state="ok"
  fi

  echo ""
  echo "[$agent]"
  echo "  command : $command_name ($command_state)"
  echo "  settings: $settings_path"
  echo "  skills  : $skills_path"
  echo "  lsp:"
  print_lsp_commands "$settings_path"
}

print_common_tools() {
  local common_tools=(
    git gh docker docker-compose playwright-cli
    rg fd jq yq bat eza fzf zoxide
    nvim micro tmux
    python3 node bun uv
    pre-commit shellcheck hadolint actionlint trivy gitleaks
    jenv java jdtls
  )
  local tool_name=""
  local available=()
  local missing=()

  for tool_name in "${common_tools[@]}"; do
    if command -v "$tool_name" >/dev/null 2>&1; then
      available+=("$tool_name")
    else
      missing+=("$tool_name")
    fi
  done

  echo ""
  echo "[common-tools]"
  if [[ "${#available[@]}" -gt 0 ]]; then
    echo "  available: ${available[*]}"
  else
    echo "  available: (none)"
  fi
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "  missing  : ${missing[*]}"
  else
    echo "  missing  : (none)"
  fi
}

echo "agent-sandbox tool inventory"
echo "home: $home_dir"

if [[ "$agent_scope" == "all" || "$agent_scope" == "codex" ]]; then
  print_agent_block \
    "codex" \
    "codex" \
    "$home_dir/.codex/settings.json" \
    "$home_dir/.codex/skills"
fi

if [[ "$agent_scope" == "all" || "$agent_scope" == "claude" ]]; then
  print_agent_block \
    "claude" \
    "claude" \
    "$home_dir/.claude/settings.json" \
    "$home_dir/.claude/skills"
fi

if [[ "$agent_scope" == "all" || "$agent_scope" == "gemini" ]]; then
  print_agent_block \
    "gemini" \
    "gemini" \
    "$home_dir/.gemini/settings.json" \
    "$home_dir/.gemini/skills"
fi

print_common_tools
