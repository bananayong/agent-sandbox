# ============================================================
# Agent Sandbox - Auto-Approve Wrappers
# ============================================================
#
# Purpose:
# - Make coding agents run with maximum autonomy by default.
# - Skip interactive permission prompts in day-to-day sandbox use.
#
# Safety:
# - This mode is intentionally dangerous.
# - Keep this file sourced only in trusted development sandboxes.

# Codex: full access, no sandbox, no approval prompts.
if command -v codex &>/dev/null; then
  codex() {
    command codex --dangerously-bypass-approvals-and-sandbox "$@"
  }
fi

# Claude: bypass permission checks for all tools/commands.
if command -v claude &>/dev/null; then
  claude() {
    command claude --dangerously-skip-permissions "$@"
  }
fi

# Gemini: YOLO approval mode auto-accepts all actions.
if command -v gemini &>/dev/null; then
  gemini() {
    command gemini --approval-mode yolo "$@"
  }
fi

# GitHub Copilot CLI:
# - gh copilot is a thin launcher for the real Copilot CLI binary.
# - We force "allow all" style flags so tools/URLs/paths are auto-approved.
_agent_sandbox_copilot_run() {
  command gh copilot -- --allow-all-tools --allow-all-urls --allow-all-paths "$@"
}

if command -v gh &>/dev/null; then
  copilot() {
    _agent_sandbox_copilot_run "$@"
  }

  gh() {
    if [[ "${1:-}" == "copilot" ]]; then
      shift
      # Keep extension lifecycle command behavior intact.
      if [[ "${1:-}" == "--remove" ]]; then
        command gh copilot --remove
      else
        _agent_sandbox_copilot_run "$@"
      fi
      return $?
    fi
    command gh "$@"
  }
fi
