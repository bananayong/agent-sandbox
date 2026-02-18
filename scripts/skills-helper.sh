#!/usr/bin/env bash
set -euo pipefail

# Helper for experimenting with skills.sh-based installs without changing
# the repository's pinned vendoring workflow.
#
# This script intentionally targets global scope by default so installed skills
# live in user home and never mutate tracked files under this repository.

usage() {
  cat <<'EOF'
Usage:
  scripts/skills-helper.sh list
  scripts/skills-helper.sh find [query...]
  scripts/skills-helper.sh add <source> [--skill <name>]... [--agent <name>]... [--project]
  scripts/skills-helper.sh check
  scripts/skills-helper.sh update
  scripts/skills-helper.sh status

Commands:
  list      List globally installed skills (skills list -g).
  find      Search skills via skills.sh registry.
  add       Install skill(s) from a source (owner/repo or Git URL).
            Defaults to global install (-g); use --project to install locally.
  check     Check for available updates for lock-tracked global installs.
  update    Update lock-tracked global installs to latest versions.
  status    Run list + check in one shot.

Notes:
  - Uses `npx skills` CLI from https://skills.sh/.
  - `skills check/update` only works for installs tracked in ~/.agents/.skill-lock.json.
  - This helper does not replace pinned vendoring (`scripts/vendor-external-skills.sh`).

Examples:
  scripts/skills-helper.sh find react performance
  scripts/skills-helper.sh add vercel-labs/agent-skills --skill vercel-react-best-practices
  scripts/skills-helper.sh add https://github.com/antfu/skills --skill vite --agent codex
  scripts/skills-helper.sh check
  scripts/skills-helper.sh update
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

run_skills() {
  npx --yes skills "$@"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

require_cmd npx

command_name="$1"
shift

case "$command_name" in
  list)
    run_skills list -g
    ;;
  find)
    run_skills find "$@"
    ;;
  add)
    if [[ $# -lt 1 ]]; then
      echo "Missing source argument for add command." >&2
      usage
      exit 1
    fi

    source_input="$1"
    shift

    install_scope="-g"
    extra_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --project)
          install_scope=""
          shift
          ;;
        --skill|--agent)
          if [[ $# -lt 2 ]]; then
            echo "Missing value for $1" >&2
            exit 1
          fi
          extra_args+=("$1" "$2")
          shift 2
          ;;
        -y|--yes|-g|--global)
          # Prevent conflicting flags; the helper controls -g/-y itself.
          shift
          ;;
        *)
          echo "Unknown add option: $1" >&2
          exit 1
          ;;
      esac
    done

    if [[ -n "$install_scope" ]]; then
      run_skills add "$source_input" "$install_scope" -y "${extra_args[@]}"
    else
      run_skills add "$source_input" -y "${extra_args[@]}"
    fi
    ;;
  check)
    run_skills check -g
    ;;
  update)
    run_skills update -g
    ;;
  status)
    run_skills list -g
    echo ""
    run_skills check -g
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage
    exit 1
    ;;
esac
