#!/bin/bash
set -euo pipefail

HOME_DIR="/home/sandbox"

# Keep tmux sockets/logs off /tmp.
# Why: some hosts enforce tiny /tmp quotas, which can make tmux startup fail
# with "No space left on device" even when the persisted home volume is healthy.
TMUX_RUNTIME_DIR="$HOME_DIR/.local/state/tmux"
if mkdir -p "$TMUX_RUNTIME_DIR"; then
  chmod 700 "$TMUX_RUNTIME_DIR" 2>/dev/null || true
  export TMUX_TMPDIR="$TMUX_RUNTIME_DIR"
else
  echo "[init] WARNING: cannot create tmux runtime dir ($TMUX_RUNTIME_DIR); falling back to /tmp" >&2
fi

# ============================================================
# First-run initialization
# ============================================================
# This script runs as container ENTRYPOINT.
# Goal: prepare user environment safely, then start requested command.
#
# Important behavior:
# - Most configs are copied only when files are missing (first run).
# - "Managed" configs (e.g. settings.json) are always overwritten to keep
#   runtime defaults in sync with the image. A diff is printed
#   before overwriting so users can see what changed.

# Copy one default config file only if destination does not exist.
# src: file baked in image (from /etc/skel)
# dest: file inside persisted user home
copy_default() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "[init] Copying default: $dest"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

# Copy shared templates from image defaults into persisted home.
# Behavior is additive and idempotent: existing user files are never overwritten.
install_default_templates() {
  local source_root="$1"
  local target_root="$2"

  if [[ ! -d "$source_root" ]]; then
    return
  fi

  mkdir -p "$target_root"

  local source_file
  local relative_path
  local target_file
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$source_root"/}"
    target_file="$target_root/$relative_path"

    if [[ -e "$target_file" ]]; then
      continue
    fi

    echo "[init] Installing default template: $target_file"
    mkdir -p "$(dirname "$target_file")"
    cp "$source_file" "$target_file"
  done < <(find "$source_root" -type f -print0 | sort -z)
}

# Update a managed config file, overwriting even if it already exists.
# Prints a unified diff before replacing so users can see what changed
# and restore manually if needed. Skips when contents are identical.
update_managed() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    echo "[init] Installing managed config: $dest"
    cp "$src" "$dest"
    return
  fi
  if diff -q "$src" "$dest" >/dev/null 2>&1; then
    return
  fi
  echo "[init] Updating managed config: $dest"
  echo "[init]   Previous content diff (- old / + new):"
  diff -u "$dest" "$src" --label "old: $dest" --label "new: $dest" | sed 's/^/[init]   /' || true
  cp "$src" "$dest"
}

# Check whether a TOML key exists under a specific section.
# Returns 0 if found, 1 otherwise.
toml_section_has_key() {
  local file="$1"
  local section="$2"
  local key="$3"

  awk -v section="$section" -v key="$key" '
    BEGIN {
      in_section = 0
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
      if ($0 ~ ("^[[:space:]]*\\[" section "\\][[:space:]]*(#.*)?$")) {
        in_section = 1
      } else {
        in_section = 0
      }
      next
    }
    in_section && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      found = 1
      exit 0
    }
    END {
      if (found == 1) {
        exit 0
      }
      exit 1
    }
  ' "$file"
}

# Insert a TOML key/value block into a section.
# - If the section exists, insert at the end of that section.
# - If the section does not exist, append a new section with the block.
insert_toml_key_into_section() {
  local file="$1"
  local section="$2"
  local block="$3"
  local tmp_file

  tmp_file="$(mktemp)"

  awk -v section="$section" -v block="$block" '
    BEGIN {
      in_section = 0
      section_seen = 0
      inserted = 0
    }
    {
      if ($0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/) {
        if (in_section && inserted == 0) {
          print block
          inserted = 1
        }
        if ($0 ~ ("^[[:space:]]*\\[" section "\\][[:space:]]*(#.*)?$")) {
          in_section = 1
          section_seen = 1
        } else {
          in_section = 0
        }
      }
      print $0
    }
    END {
      if (section_seen == 1 && inserted == 0) {
        print block
      }
      if (section_seen == 0) {
        print ""
        print "[" section "]"
        print block
      }
    }
  ' "$file" > "$tmp_file"

  mv "$tmp_file" "$file"
}

# Ensure Codex config contains managed defaults required by this image:
# - [tui].status_line
# - [features].undo
# - [features].multi_agent
# - [features].apps
# - [agents].max_threads
# Rules:
# - If config does not exist: install the image default as-is.
# - If a key already exists: keep user customization.
# - If a key is missing: insert only that key into the right section.
ensure_codex_status_line() {
  local src="$1"
  local dest="$2"
  local status_block

  mkdir -p "$(dirname "$dest")"

  if [[ ! -f "$dest" ]]; then
    echo "[init] Installing Codex default config: $dest"
    cp "$src" "$dest"
    return
  fi

  status_block='status_line = [
  "model-with-reasoning",
  "current-dir",
  "git-branch",
  "context-used",
  "total-input-tokens",
  "total-output-tokens",
  "five-hour-limit",
  "weekly-limit",
]'

  if ! toml_section_has_key "$dest" "tui" "status_line"; then
    echo "[init] Updating Codex config with default status line: $dest"
    insert_toml_key_into_section "$dest" "tui" "$status_block"
  fi

  if ! toml_section_has_key "$dest" "features" "multi_agent"; then
    echo "[init] Enabling Codex default multi-agent feature: $dest"
    insert_toml_key_into_section "$dest" "features" "multi_agent = true"
  fi

  if ! toml_section_has_key "$dest" "features" "undo"; then
    echo "[init] Enabling Codex default undo feature: $dest"
    insert_toml_key_into_section "$dest" "features" "undo = true"
  fi

  if ! toml_section_has_key "$dest" "features" "apps"; then
    echo "[init] Enabling Codex default apps feature: $dest"
    insert_toml_key_into_section "$dest" "features" "apps = true"
  fi

  if ! toml_section_has_key "$dest" "agents" "max_threads"; then
    echo "[init] Setting Codex default agent max_threads: $dest"
    insert_toml_key_into_section "$dest" "agents" "max_threads = 12"
  fi
}

# Install shared skills from image into one agent's skill directory.
# By default behavior is additive: existing skills are never overwritten.
# Optional 3rd arg is a comma-separated exclude list by skill folder name.
# Optional 4th arg is a comma-separated force-sync list: matching skills are
# overwritten from image defaults every startup to keep managed guidance fresh.
install_shared_skills() {
  local source_root="$1"
  local target_root="$2"
  local exclude_csv="${3:-}"
  local force_sync_csv="${4:-}"

  if [[ ! -d "$source_root" ]]; then
    return
  fi

  mkdir -p "$target_root"

  local source_skill
  for source_skill in "$source_root"/*; do
    if [[ ! -d "$source_skill" ]] || [[ ! -f "$source_skill/SKILL.md" ]]; then
      continue
    fi

    local skill_name
    local target_skill
    local should_force_sync=0
    skill_name="$(basename "$source_skill")"
    target_skill="$target_root/$skill_name"

    if [[ -n "$exclude_csv" ]]; then
      local exclude_name
      local should_skip=0
      IFS=',' read -r -a exclude_list <<< "$exclude_csv"
      for exclude_name in "${exclude_list[@]}"; do
        if [[ "$skill_name" == "$exclude_name" ]]; then
          should_skip=1
          break
        fi
      done
      if [[ "$should_skip" -eq 1 ]]; then
        continue
      fi
    fi

    if [[ -n "$force_sync_csv" ]]; then
      local force_sync_name
      IFS=',' read -r -a force_sync_list <<< "$force_sync_csv"
      for force_sync_name in "${force_sync_list[@]}"; do
        if [[ "$skill_name" == "$force_sync_name" ]]; then
          should_force_sync=1
          break
        fi
      done
    fi

    # Respect user-managed/customized skills with the same name unless this
    # skill is explicitly managed via force-sync list.
    if [[ -e "$target_skill" ]] && [[ "$should_force_sync" -ne 1 ]]; then
      continue
    fi

    if [[ "$should_force_sync" -eq 1 ]] && [[ -e "$target_skill" ]]; then
      echo "[init] Updating managed shared skill: $target_skill"
      rm -rf "$target_skill"
    else
      echo "[init] Installing shared skill: $target_skill"
    fi

    cp -r "$source_skill" "$target_skill"
  done
}

copy_default /etc/skel/.default.zshrc        "$HOME_DIR/.zshrc"
copy_default /etc/skel/.default.zimrc         "$HOME_DIR/.zimrc"
copy_default /etc/skel/.default.tmux.conf     "$HOME_DIR/.tmux.conf"
copy_default /etc/skel/.default.vimrc         "$HOME_DIR/.vimrc"
copy_default /etc/skel/.config/nvim/init.lua  "$HOME_DIR/.config/nvim/init.lua"
copy_default /etc/skel/.config/micro/settings.json "$HOME_DIR/.config/micro/settings.json"
copy_default /etc/skel/.config/micro/bindings.json "$HOME_DIR/.config/micro/bindings.json"
update_managed /etc/skel/.config/starship.toml "$HOME_DIR/.config/starship.toml"
copy_default /etc/skel/.default.pre-commit-config.yaml "$HOME_DIR/.pre-commit-config.yaml.template"
copy_default /etc/skel/.config/agent-sandbox/TOOLS.md  "$HOME_DIR/.config/agent-sandbox/TOOLS.md"
update_managed /etc/skel/.config/agent-sandbox/auto-approve.zsh "$HOME_DIR/.config/agent-sandbox/auto-approve.zsh"
update_managed /etc/skel/.config/agent-sandbox/editor-defaults.zsh "$HOME_DIR/.config/agent-sandbox/editor-defaults.zsh"
install_default_templates /etc/skel/.agent-sandbox/templates "$HOME_DIR/.agent-sandbox/templates"

# Existing users may already have a persisted ~/.zshrc from older images.
# Add a one-time source hook so new auto-approve wrappers are loaded without
# forcing users to reset their sandbox home or manually edit dotfiles.
AUTO_APPROVE_HOOK='[[ -f ~/.config/agent-sandbox/auto-approve.zsh ]] && source ~/.config/agent-sandbox/auto-approve.zsh'
if [[ -f "$HOME_DIR/.zshrc" ]] && ! grep -Fq "$AUTO_APPROVE_HOOK" "$HOME_DIR/.zshrc"; then
  {
    echo ""
    echo "# Agent auto-approve wrappers (managed by agent-sandbox)."
    echo "$AUTO_APPROVE_HOOK"
  } >> "$HOME_DIR/.zshrc"
fi

# Ensure editor defaults are applied for both new and existing persisted homes.
# This hook is appended at the end so it overrides stale legacy defaults.
EDITOR_DEFAULTS_HOOK='[[ -f ~/.config/agent-sandbox/editor-defaults.zsh ]] && source ~/.config/agent-sandbox/editor-defaults.zsh'
if [[ -f "$HOME_DIR/.zshrc" ]] && ! grep -Fq "$EDITOR_DEFAULTS_HOOK" "$HOME_DIR/.zshrc"; then
  {
    echo ""
    echo "# Agent editor defaults (managed by agent-sandbox)."
    echo "$EDITOR_DEFAULTS_HOOK"
  } >> "$HOME_DIR/.zshrc"
fi

# Claude CLI reads this file very early. Ensure it exists to avoid repeated
# ENOENT exceptions during startup when home was freshly initialized/reset.
if [[ ! -f "$HOME_DIR/.claude/remote-settings.json" ]]; then
  mkdir -p "$HOME_DIR/.claude"
  printf '{}\n' > "$HOME_DIR/.claude/remote-settings.json"
fi

# Copy Claude Code slash commands if the commands directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/commands" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/commands" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code slash commands..."
  mkdir -p "$HOME_DIR/.claude/commands"
  cp -r /etc/skel/.claude/commands/* "$HOME_DIR/.claude/commands/" 2>/dev/null || true
fi

# Copy Claude Code skills if the skills directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/skills" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/skills" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code skills..."
  mkdir -p "$HOME_DIR/.claude/skills"
  cp -r /etc/skel/.claude/skills/* "$HOME_DIR/.claude/skills/" 2>/dev/null || true
fi

# Copy Claude Code agents if the agents directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/agents" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/agents" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code agents..."
  mkdir -p "$HOME_DIR/.claude/agents"
  cp -r /etc/skel/.claude/agents/* "$HOME_DIR/.claude/agents/" 2>/dev/null || true
fi

# Install vendored shared skills for coding agents.
# Codex/Gemini keep their native "skill-creator" to avoid overriding
# built-in workflow behavior with a third-party variant.
SHARED_SKILLS_ROOT="/opt/agent-sandbox/skills"
# Keep this list narrow: only skills that should be centrally managed and
# always updated even for existing persisted homes.
FORCE_SYNC_SHARED_SKILLS="playwright-efficient-web-research"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.claude/skills" "" "$FORCE_SYNC_SHARED_SKILLS"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.codex/skills" "skill-creator" "$FORCE_SYNC_SHARED_SKILLS"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.gemini/skills" "skill-creator" "$FORCE_SYNC_SHARED_SKILLS"

# Agent settings are managed: always synced with image defaults.
# This ensures runtime defaults reach existing users after image updates.
# WARNING: this overwrites user edits to settings.json (diff is printed first).
update_managed /etc/skel/.claude/settings.json "$HOME_DIR/.claude/settings.json"
update_managed /etc/skel/.codex/settings.json "$HOME_DIR/.codex/settings.json"
update_managed /etc/skel/.gemini/settings.json "$HOME_DIR/.gemini/settings.json"

# Copy MCP server config template if not already present.
copy_default /etc/skel/.claude/.mcp.json "$HOME_DIR/.claude/.mcp.json"
# Seed Codex bridge skill for Ars Contexta reference-mode usage.
copy_default /etc/skel/.codex/skills/arscontexta-bridge/SKILL.md "$HOME_DIR/.codex/skills/arscontexta-bridge/SKILL.md"

# Codex CLI uses config.toml for TUI/runtime preferences.
# Keep existing user config, but ensure managed default keys exist.
ensure_codex_status_line /etc/skel/.codex/config.toml "$HOME_DIR/.codex/config.toml"

# Runtime safety defaults for Claude network stability.
# Keep these here (entrypoint) as a final fallback so they still apply even
# when container is launched via a path that bypasses run.sh defaults.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export DISABLE_ERROR_REPORTING="1"
export DISABLE_TELEMETRY="1"
export DISABLE_AUTOUPDATER="1"
if [[ "${NODE_OPTIONS:-}" != *"--tls-max-v1.2"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-max-v1.2"
fi
if [[ "${NODE_OPTIONS:-}" != *"--tls-min-v1.2"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-min-v1.2"
fi
if [[ "${NODE_OPTIONS:-}" != *"--dns-result-order=ipv4first"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first"
fi

# Quick DNS sanity check for Claude API hostname.
# This catches common cases where container DNS points to unreachable stubs.
print_dns_diagnostics() {
  if getent hosts api.anthropic.com >/dev/null 2>&1; then
    return
  fi

  local nameservers
  nameservers="$(awk '/^nameserver[[:space:]]+/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  nameservers="${nameservers% }"

  echo "[init] WARNING: DNS lookup failed for api.anthropic.com"
  if [[ -n "$nameservers" ]]; then
    echo "  /etc/resolv.conf nameservers: $nameservers"
  else
    echo "  /etc/resolv.conf has no nameserver entries."
  fi
  echo "  Tip: restart with AGENT_SANDBOX_DNS_SERVERS='<ipv4_dns1>,<ipv4_dns2>' ./run.sh ."
}

print_dns_diagnostics

# Refresh tealdeer cache in a resilient, non-blocking way.
# Why this exists:
# - `tldr --update` occasionally fails with "InvalidArchive" in some environments.
# - Startup should continue even when updates fail.
#
# Strategy:
# - bounded retries with a timeout per attempt
# - if output mentions InvalidArchive, clear cache dirs and retry
update_tealdeer_cache() {
  if ! command -v tldr &>/dev/null; then
    return 0
  fi

  local max_attempts=3
  local update_timeout_seconds=30
  local attempt=1

  while [[ "$attempt" -le "$max_attempts" ]]; do
    local update_log
    local update_exit=0
    update_log="$(mktemp)"

    if timeout --kill-after=10 "$update_timeout_seconds" tldr --update </dev/null >"$update_log" 2>&1; then
      rm -f "$update_log"
      return 0
    fi
    update_exit=$?

    if grep -Eqi 'InvalidArchive|invalid[[:space:]_-]*archive' "$update_log"; then
      local cache_paths=(
        "${XDG_CACHE_HOME:-$HOME_DIR/.cache}/tealdeer"
        "${XDG_DATA_HOME:-$HOME_DIR/.local/share}/tealdeer"
      )
      if [[ -n "${TLDR_CACHE_DIR:-}" ]]; then
        cache_paths+=("$TLDR_CACHE_DIR")
      fi

      echo "[init]   WARNING: tldr --update hit InvalidArchive (attempt $attempt/$max_attempts)." >&2
      echo "[init]   Clearing tealdeer cache before retry..." >&2

      local cache_path
      for cache_path in "${cache_paths[@]}"; do
        rm -rf "$cache_path" 2>/dev/null || true
      done
    else
      echo "[init]   WARNING: tldr --update failed or timed out (attempt $attempt/$max_attempts, exit=$update_exit)." >&2
    fi

    sed 's/^/[init]   /' "$update_log" >&2 || true
    rm -f "$update_log"
    attempt=$((attempt + 1))
  done

  echo "[init]   WARNING: Continuing startup without refreshed tealdeer cache." >&2
  return 0
}

# Install a curated set of Micro plugins for Vim/Neovim-like workflows.
# Missing plugins are installed once and retried automatically on later starts.
install_micro_plugins() {
  if ! command -v micro &>/dev/null; then
    return 0
  fi

  local micro_config_dir="$HOME_DIR/.config/micro"
  local micro_plug_dir="$micro_config_dir/plug"
  local micro_plugins=(
    detectindent
    fzf
    lsp
    quickfix
    bookmark
    manipulator
    nordcolors
    monokai-dark
    gotham-colors
  )
  local missing_micro_plugins=()
  local plugin_name

  mkdir -p "$micro_config_dir"
  for plugin_name in "${micro_plugins[@]}"; do
    if [[ ! -d "$micro_plug_dir/$plugin_name" ]]; then
      missing_micro_plugins+=("$plugin_name")
    fi
  done

  if [[ "${#missing_micro_plugins[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "[init] Installing micro plugins: ${missing_micro_plugins[*]}..."
  if ! timeout --kill-after=10 120 micro -plugin install "${missing_micro_plugins[@]}" </dev/null; then
    echo "[init]   WARNING: micro plugin install failed or timed out (non-blocking)" >&2
  fi
}

find_playwright_chromium_binary() {
  local browsers_root="$1"

  if [[ ! -d "$browsers_root" ]]; then
    return 1
  fi

  find "$browsers_root" -type f \
    \( -path '*/chrome-linux/chrome' -o -path '*/chrome-linux64/chrome' -o -path '*/chrome-linux-arm64/chrome' \) \
    -print -quit
}

ensure_playwright_chromium() {
  if ! command -v playwright-cli &>/dev/null; then
    return 0
  fi

  local primary_root="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
  local fallback_root="${XDG_CACHE_HOME:-$HOME_DIR/.cache}/ms-playwright"
  local selected_tmpdir=""
  local lock_file="${XDG_CACHE_HOME:-$HOME_DIR/.cache}/agent-sandbox/playwright-chromium.lock"
  local lock_fd=""
  local bootstrap_dir=""
  local install_log=""
  local candidate_root=""
  local playwright_installer_cli=""

  choose_playwright_tmpdir() {
    local candidate
    local probe_dir=""
    local candidates=()

    if [[ -n "${TMPDIR:-}" ]]; then
      candidates+=("$TMPDIR")
    fi
    candidates+=(
      "${XDG_CACHE_HOME:-$HOME_DIR/.cache}/agent-sandbox/tmp"
      "$HOME_DIR/.cache/agent-sandbox/tmp"
      "/tmp"
    )

    for candidate in "${candidates[@]}"; do
      if [[ -z "$candidate" ]]; then
        continue
      fi
      if ! mkdir -p "$candidate" >/dev/null 2>&1; then
        continue
      fi
      if probe_dir="$(mktemp -d "$candidate/playwright-tmp.XXXXXXXXXX" 2>/dev/null)"; then
        rm -rf "$probe_dir"
        echo "$candidate"
        return 0
      fi
    done
    return 1
  }

  resolve_playwright_installer_cli() {
    local npm_root=""
    local candidate=""

    if command -v npm &>/dev/null; then
      npm_root="$(npm root -g 2>/dev/null || true)"
      if [[ -n "$npm_root" ]]; then
        candidate="$npm_root/@playwright/cli/node_modules/playwright/cli.js"
        if [[ -f "$candidate" ]]; then
          echo "$candidate"
          return 0
        fi
      fi
    fi

    for candidate in \
      "/usr/lib/node_modules/@playwright/cli/node_modules/playwright/cli.js" \
      "/usr/local/lib/node_modules/@playwright/cli/node_modules/playwright/cli.js"; do
      if [[ -f "$candidate" ]]; then
        echo "$candidate"
        return 0
      fi
    done

    return 1
  }

  prepare_playwright_install_root() {
    local install_root="$1"
    local linked_target=""

    # Dedup mode can leave fallback as a symlink to /ms-playwright, which is
    # read-only for the sandbox user. Convert back to a writable cache dir
    # before attempting self-heal installs.
    if [[ -L "$install_root" ]]; then
      linked_target="$(readlink "$install_root" 2>/dev/null || true)"
      echo "[init]   Playwright fallback cache points to ${linked_target:-unknown target}; recreating writable cache dir at $install_root"
      if ! rm -f "$install_root" 2>/dev/null; then
        return 1
      fi
    fi

    if [[ -e "$install_root" ]] && [[ ! -d "$install_root" ]]; then
      if ! rm -rf "$install_root" 2>/dev/null; then
        return 1
      fi
    fi

    if ! mkdir -p "$install_root" 2>/dev/null; then
      return 1
    fi
    if [[ ! -w "$install_root" ]]; then
      return 1
    fi

    return 0
  }

  validate_playwright_root() {
    local browsers_root="$1"
    local candidate_bin=""

    if ! candidate_bin="$(find_playwright_chromium_binary "$browsers_root")"; then
      return 1
    fi
    if [[ ! -x "$candidate_bin" ]]; then
      return 1
    fi

    if ! "$candidate_bin" --version >/dev/null 2>&1; then
      return 1
    fi

    return 0
  }

  probe_playwright_launch() {
    local browsers_root="$1"
    local probe_tmpdir="$2"
    local probe_timeout_seconds="${3:-45}"
    local probe_dir=""
    local probe_session="playwright-verify-$$"

    if ! probe_dir="$(mktemp -d "$probe_tmpdir/playwright-probe.XXXXXXXXXX" 2>/dev/null)"; then
      return 1
    fi

    if (
      cd "$probe_dir"
      timeout --kill-after=10 "$probe_timeout_seconds" env TMPDIR="$probe_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" open about:blank --browser=chromium >/dev/null 2>&1
    ); then
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" close >/dev/null 2>&1 || true
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" delete-data >/dev/null 2>&1 || true
      rm -rf "$probe_dir"
      return 0
    fi

    timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
      playwright-cli -s="$probe_session" close >/dev/null 2>&1 || true
    timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
      playwright-cli -s="$probe_session" delete-data >/dev/null 2>&1 || true
    rm -rf "$probe_dir"
    return 1
  }

  dedupe_playwright_fallback_cache() {
    local canonical_root="$1"
    local duplicate_root="$2"
    local canonical_bin=""
    local duplicate_bin=""
    local canonical_revision=""
    local duplicate_revision=""
    local linked_target=""

    if [[ "$canonical_root" == "$duplicate_root" ]]; then
      return 0
    fi
    if [[ ! -d "$canonical_root" ]] || [[ ! -e "$duplicate_root" ]]; then
      return 0
    fi

    if [[ -L "$duplicate_root" ]]; then
      linked_target="$(readlink "$duplicate_root" 2>/dev/null || true)"
      if [[ "$linked_target" == "$canonical_root" ]]; then
        return 0
      fi
    fi

    if ! canonical_bin="$(find_playwright_chromium_binary "$canonical_root" 2>/dev/null)"; then
      return 0
    fi

    duplicate_bin="$(find_playwright_chromium_binary "$duplicate_root" 2>/dev/null || true)"
    if [[ -n "$duplicate_bin" ]]; then
      canonical_revision="$(basename "$(dirname "$(dirname "$canonical_bin")")")"
      duplicate_revision="$(basename "$(dirname "$(dirname "$duplicate_bin")")")"
      # Keep fallback cache untouched when it contains a different Chromium revision.
      if [[ "$canonical_revision" != "$duplicate_revision" ]]; then
        return 0
      fi
    fi

    mkdir -p "$(dirname "$duplicate_root")" 2>/dev/null || true
    rm -rf "$duplicate_root" 2>/dev/null || true
    if ln -s "$canonical_root" "$duplicate_root" 2>/dev/null; then
      echo "[init] Deduplicated Playwright fallback cache: $duplicate_root -> $canonical_root"
    fi
  }

  cleanup_playwright_bootstrap() {
    if [[ -n "$bootstrap_dir" ]]; then
      rm -rf "$bootstrap_dir" 2>/dev/null || true
    fi
    if [[ -n "$install_log" ]]; then
      rm -f "$install_log" 2>/dev/null || true
    fi
    if [[ -n "${lock_fd:-}" ]]; then
      # zsh can treat eval'ed fd close as a command and return 127.
      exec {lock_fd}>&- 2>/dev/null || true
      lock_fd=""
    fi
  }

  fail_playwright_bootstrap() {
    local reason="$1"
    echo "[init] ERROR: Playwright Chromium companion bootstrap failed (${reason})." >&2
    cleanup_playwright_bootstrap
    return 1
  }

  if ! selected_tmpdir="$(choose_playwright_tmpdir)"; then
    fail_playwright_bootstrap "no writable TMPDIR candidate"
    return 1
  fi

  if validate_playwright_root "$primary_root" && probe_playwright_launch "$primary_root" "$selected_tmpdir"; then
    export PLAYWRIGHT_BROWSERS_PATH="$primary_root"
    dedupe_playwright_fallback_cache "$primary_root" "$fallback_root"
    return 0
  fi

  if validate_playwright_root "$fallback_root" && probe_playwright_launch "$fallback_root" "$selected_tmpdir"; then
    export PLAYWRIGHT_BROWSERS_PATH="$fallback_root"
    return 0
  fi

  if ! mkdir -p "$(dirname "$lock_file")"; then
    fail_playwright_bootstrap "cannot prepare lock directory"
    return 1
  fi
  if ! prepare_playwright_install_root "$fallback_root"; then
    fail_playwright_bootstrap "cannot prepare lock/cache directories"
    return 1
  fi
  if command -v flock &>/dev/null; then
    if ! exec {lock_fd}>"$lock_file"; then
      fail_playwright_bootstrap "cannot open lock file $lock_file"
      return 1
    fi
    if ! flock -w 120 "$lock_fd"; then
      fail_playwright_bootstrap "cannot acquire install lock"
      return 1
    fi
  fi

  # Another shell may have repaired the payload while we were waiting for the lock.
  if validate_playwright_root "$primary_root" && probe_playwright_launch "$primary_root" "$selected_tmpdir"; then
    export PLAYWRIGHT_BROWSERS_PATH="$primary_root"
    dedupe_playwright_fallback_cache "$primary_root" "$fallback_root"
    cleanup_playwright_bootstrap
    return 0
  fi
  if validate_playwright_root "$fallback_root" && probe_playwright_launch "$fallback_root" "$selected_tmpdir"; then
    export PLAYWRIGHT_BROWSERS_PATH="$fallback_root"
    cleanup_playwright_bootstrap
    return 0
  fi

  if ! bootstrap_dir="$(mktemp -d "$selected_tmpdir/playwright-bootstrap.XXXXXXXXXX" 2>/dev/null)"; then
    fail_playwright_bootstrap "cannot create isolated bootstrap directory"
    return 1
  fi
  if ! mkdir -p "$bootstrap_dir/.playwright"; then
    fail_playwright_bootstrap "cannot create playwright config directory"
    return 1
  fi
  printf '{\n  "browser": {\n    "browserName": "chromium"\n  }\n}\n' > "$bootstrap_dir/.playwright/cli.config.json"

  if ! install_log="$(mktemp "$selected_tmpdir/playwright-install.XXXXXXXXXX.log" 2>/dev/null)"; then
    fail_playwright_bootstrap "cannot allocate install log file"
    return 1
  fi

  if ! playwright_installer_cli="$(resolve_playwright_installer_cli)"; then
    fail_playwright_bootstrap "cannot resolve playwright chromium installer"
    return 1
  fi
  if ! prepare_playwright_install_root "$fallback_root"; then
    fail_playwright_bootstrap "fallback cache root is not writable"
    return 1
  fi

  if ! (
    cd "$bootstrap_dir"
    timeout --kill-after=10 300 env TMPDIR="$selected_tmpdir" PLAYWRIGHT_BROWSERS_PATH="$fallback_root" \
      node "$playwright_installer_cli" install chromium </dev/null >"$install_log" 2>&1
  ); then
    echo "[init]   Playwright install output:" >&2
    if [[ -s "$install_log" ]]; then
      sed 's/^/[init]   /' "$install_log" >&2 || true
    else
      echo "[init]   (no installer output captured)" >&2
    fi
    fail_playwright_bootstrap "playwright chromium install failed"
    return 1
  fi

  for candidate_root in "$fallback_root" "$primary_root"; do
    if validate_playwright_root "$candidate_root" && probe_playwright_launch "$candidate_root" "$selected_tmpdir"; then
      export PLAYWRIGHT_BROWSERS_PATH="$candidate_root"
      if [[ "$candidate_root" == "$primary_root" ]]; then
        dedupe_playwright_fallback_cache "$primary_root" "$fallback_root"
      fi
      echo "[init] Recovered Playwright Chromium companion in $PLAYWRIGHT_BROWSERS_PATH"
      cleanup_playwright_bootstrap
      return 0
    fi
  done

  # Newer playwright-cli layouts may not expose the legacy marker/path shape.
  # If direct launch works, accept the runtime as healthy.
  for candidate_root in "$fallback_root" "$primary_root"; do
    if probe_playwright_launch "$candidate_root" "$selected_tmpdir" 180; then
      export PLAYWRIGHT_BROWSERS_PATH="$candidate_root"
      if [[ "$candidate_root" == "$primary_root" ]]; then
        dedupe_playwright_fallback_cache "$primary_root" "$fallback_root"
      fi
      echo "[init]   WARNING: Playwright payload layout check skipped; launch probe succeeded for $candidate_root" >&2
      echo "[init] Recovered Playwright Chromium companion in $PLAYWRIGHT_BROWSERS_PATH"
      cleanup_playwright_bootstrap
      return 0
    fi
  done

  echo "[init]   Playwright install output:" >&2
  sed 's/^/[init]   /' "$install_log" >&2 || true
  fail_playwright_bootstrap "fallback chromium payload is invalid"
  return 1
}

# ============================================================
# Zimfw bootstrap
# ============================================================
ZIM_HOME="$HOME_DIR/.zim"

# Download only zimfw core script.
# We intentionally avoid full installer because it can overwrite .zshrc.
if [[ ! -f "$ZIM_HOME/zimfw.zsh" ]]; then
  echo "[init] Downloading zimfw..."
  mkdir -p "$ZIM_HOME"
  if ! timeout --kill-after=10 45 curl -fsSL "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh" \
    -o "$ZIM_HOME/zimfw.zsh" </dev/null; then
    echo "[init]   WARNING: zimfw download failed or timed out (non-blocking)" >&2
    rm -f "$ZIM_HOME/zimfw.zsh"
  fi
fi

# Install modules only once.
# init.zsh is generated by zimfw install and indicates bootstrap completion.
if [[ -f "$ZIM_HOME/zimfw.zsh" ]]; then
  if [[ ! -f "$ZIM_HOME/init.zsh" ]]; then
    echo "[init] Installing zim modules..."
    # Keep startup resilient: do not fail entire container start on transient network errors.
    if ! timeout --kill-after=10 90 env ZIM_HOME="$ZIM_HOME" zsh "$ZIM_HOME/zimfw.zsh" install -q </dev/null; then
      echo "[init]   WARNING: zim module install failed or timed out (non-blocking)" >&2
    fi
  fi
fi

# ============================================================
# One-time tool setup
# ============================================================
# These are idempotent checks: safe across repeated container starts.

# Configure git-delta as pager when available.
# We avoid re-writing config every run by checking existing value first.
if command -v delta &>/dev/null; then
  if [[ "$(git config --global core.pager 2>/dev/null)" != "delta" ]]; then
    echo "[init] Configuring git-delta..."
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global delta.line-numbers true
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
  fi
fi

# Set default git editor to nvim.
# Preserve explicit user customization, but migrate previous micro default.
if command -v nvim &>/dev/null; then
  current_git_editor="$(git config --global core.editor 2>/dev/null || true)"
  if [[ -z "$current_git_editor" ]] || [[ "$current_git_editor" == "micro" ]]; then
    git config --global core.editor nvim
  fi
fi

# Install missing Micro plugins from the curated default set.
install_micro_plugins

# Ensure Playwright Chromium companion browser is always ready before handoff.
ensure_playwright_chromium

# Install gh-copilot extension in user scope (inside persisted home).
# This happens once because extension directory is checked first.
if command -v gh &>/dev/null; then
  if [[ ! -d "$HOME_DIR/.local/share/gh/extensions/gh-copilot" ]]; then
    echo "[init] Installing GitHub Copilot CLI..."
    timeout --kill-after=10 30 gh extension install github/gh-copilot </dev/null || true
  fi
fi

# Refresh local tldr pages cache in the background.
# This keeps startup fast even when network is slow.
update_tealdeer_cache &

# Install TPM (Tmux Plugin Manager) and ensure default tmux plugins are present.
# Retry on later startups when plugin install fails transiently.
TPM_PLUGIN_ROOT="$HOME_DIR/.tmux/plugins"
TPM_DIR="$TPM_PLUGIN_ROOT/tpm"
REQUIRED_TMUX_PLUGINS=(tmux-resurrect tmux-continuum)

if [[ ! -d "$TPM_DIR" ]]; then
  echo "[init] Installing TPM (Tmux Plugin Manager)..."
  if ! timeout --kill-after=10 30 git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" </dev/null; then
    echo "[init]   WARNING: TPM clone failed or timed out (non-blocking)" >&2
    rm -rf "$TPM_DIR"
  fi
fi

if [[ -d "$TPM_DIR" ]] && command -v tmux &>/dev/null; then
  missing_tmux_plugins=()
  for plugin_name in "${REQUIRED_TMUX_PLUGINS[@]}"; do
    if [[ ! -d "$TPM_PLUGIN_ROOT/$plugin_name" ]]; then
      missing_tmux_plugins+=("$plugin_name")
    fi
  done

  if [[ "${#missing_tmux_plugins[@]}" -gt 0 ]]; then
    echo "[init] Installing tmux plugins: ${missing_tmux_plugins[*]}..."

    # TPM's install script reads TMUX_PLUGIN_MANAGER_PATH from tmux server env.
    # Keep a short-lived detached tmux session while installing so the server
    # stays alive and retains the environment variable in non-interactive
    # startup contexts.
    tmux_bootstrap_session="__agent_sandbox_tpm_bootstrap_$$"
    tmux_bootstrap_session_created=0
    tmux_server_ready=0
    if tmux -f "$HOME_DIR/.tmux.conf" new-session -d -s "$tmux_bootstrap_session" >/dev/null 2>&1; then
      tmux_bootstrap_session_created=1
      tmux_server_ready=1
    else
      if tmux -f "$HOME_DIR/.tmux.conf" start-server >/dev/null 2>&1; then
        tmux_server_ready=1
      fi
    fi

    if [[ "$tmux_server_ready" -eq 1 ]]; then
      tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TPM_PLUGIN_ROOT" >/dev/null 2>&1 || true
      if ! timeout --kill-after=10 60 "$TPM_DIR/bin/install_plugins" </dev/null; then
        echo "[init]   WARNING: tmux plugin install failed or timed out (non-blocking)" >&2
      fi
    else
      echo "[init]   WARNING: tmux server startup failed; skipping tmux plugin install (non-blocking)" >&2
    fi

    if [[ "$tmux_bootstrap_session_created" -eq 1 ]]; then
      tmux kill-session -t "$tmux_bootstrap_session" >/dev/null 2>&1 || true
    fi
  fi
fi

# Install broot shell launcher script if broot exists.
if command -v broot &>/dev/null; then
  if [[ ! -f "$HOME_DIR/.config/broot/launcher/bash/br" ]]; then
    echo "[init] Initializing broot..."
    if ! timeout --kill-after=10 30 broot --install </dev/null; then
      echo "[init]   WARNING: broot init failed or timed out (non-blocking)" >&2
    fi
  fi
fi

# Superpowers skills (obra/superpowers) for Claude Code and Codex.
# Installs on first run; sentinel files prevent repeated installs.
#
# IMPORTANT: all commands use </dev/null to prevent interactive prompts from
# blocking the entrypoint (no TTY during container startup). --kill-after
# sends SIGKILL after grace period because Node.js (claude CLI) may ignore
# SIGTERM and hang indefinitely.
SUPERPOWERS_REPO="https://github.com/obra/superpowers.git"

# Check if Superpowers marketplace exists in Claude plugin storage.
claude_has_superpowers_marketplace() {
  local marketplace_dir="$HOME_DIR/.claude/plugins/marketplaces/superpowers-marketplace"
  [[ -d "$marketplace_dir" ]] && [[ -n "$(ls -A "$marketplace_dir" 2>/dev/null)" ]]
}

# Check if Claude already has Superpowers installed.
# We validate both metadata and on-disk plugin cache to avoid false positives
# from stale installed_plugins.json entries.
claude_has_superpowers_plugin() {
  local plugins_json="$HOME_DIR/.claude/plugins/installed_plugins.json"
  local plugin_cache_dir="$HOME_DIR/.claude/plugins/cache/superpowers-marketplace/superpowers"

  [[ -f "$plugins_json" ]] \
    && grep -Fq '"superpowers@superpowers-marketplace"' "$plugins_json" \
    && [[ -d "$plugin_cache_dir" ]] \
    && [[ -n "$(ls -A "$plugin_cache_dir" 2>/dev/null)" ]]
}

# Claude Code: install via plugin marketplace.
# The CLAUDECODE env var must be unset so `claude plugin` works outside a session.
CLAUDE_SP_SENTINEL="$HOME_DIR/.claude/plugins/.superpowers-installed"
if command -v claude &>/dev/null && [[ ! -f "$CLAUDE_SP_SENTINEL" ]]; then
  if claude_has_superpowers_plugin; then
    echo "[init] Superpowers plugin already present for Claude Code."
    mkdir -p "$(dirname "$CLAUDE_SP_SENTINEL")"
    touch "$CLAUDE_SP_SENTINEL"
  else
    echo "[init] Installing Superpowers plugin for Claude Code..."
    claude_marketplace_ready=0
    claude_marketplace_log="$(mktemp)"
    claude_marketplace_exit=0
    if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin marketplace add obra/superpowers-marketplace </dev/null >"$claude_marketplace_log" 2>&1; then
      claude_marketplace_exit=$?
    fi

    # Determine readiness from filesystem state instead of CLI error strings.
    if claude_has_superpowers_marketplace; then
      claude_marketplace_ready=1
    fi

    if [[ "$claude_marketplace_ready" -ne 1 ]]; then
      echo "[init]   WARNING: Superpowers marketplace add failed or timed out (non-blocking)" >&2
      echo "[init]   Exit code: $claude_marketplace_exit" >&2
      sed 's/^/[init]   /' "$claude_marketplace_log" >&2 || true
    fi
    rm -f "$claude_marketplace_log"

    if [[ "$claude_marketplace_ready" -eq 1 ]]; then
      claude_install_log="$(mktemp)"
      claude_install_exit=0
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin install superpowers@superpowers-marketplace </dev/null >"$claude_install_log" 2>&1; then
        claude_install_exit=$?
      fi

      # Validate post-state from metadata so we can mark completion idempotently.
      if claude_has_superpowers_plugin; then
        mkdir -p "$(dirname "$CLAUDE_SP_SENTINEL")"
        touch "$CLAUDE_SP_SENTINEL"
      else
        echo "[init]   WARNING: Superpowers plugin install failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $claude_install_exit" >&2
        sed 's/^/[init]   /' "$claude_install_log" >&2 || true
      fi
      rm -f "$claude_install_log"
    fi
  fi
fi

# Codex: clone repo and symlink skills into Codex skill discovery path.
CODEX_SP_SENTINEL="$HOME_DIR/.codex/.superpowers-installed"
if command -v codex &>/dev/null && [[ ! -f "$CODEX_SP_SENTINEL" ]]; then
  echo "[init] Installing Superpowers skills for Codex..."
  if [[ ! -d "$HOME_DIR/.codex/superpowers" ]]; then
    # Timeout + kill-after prevents a hanging clone from blocking container startup.
    if ! timeout --kill-after=10 30 git clone --depth 1 "$SUPERPOWERS_REPO" "$HOME_DIR/.codex/superpowers" </dev/null; then
      echo "[init]   WARNING: Superpowers clone failed or timed out for Codex (non-blocking)" >&2
      # Remove partial clone so the next startup retries cleanly.
      rm -rf "$HOME_DIR/.codex/superpowers"
    fi
  fi
  if [[ -d "$HOME_DIR/.codex/superpowers/skills" ]]; then
    mkdir -p "$HOME_DIR/.agents/skills"
    ln -sfn "$HOME_DIR/.codex/superpowers/skills" "$HOME_DIR/.agents/skills/superpowers"
    mkdir -p "$(dirname "$CODEX_SP_SENTINEL")"
    touch "$CODEX_SP_SENTINEL"
  fi
fi

# Codex: clone Ars Contexta as a local reference bundle.
# Codex has no Claude plugin runtime, so this is a docs/methodology bridge.
CODEX_ARSCONTEXTA_REPO="https://github.com/agenticnotetaking/arscontexta.git"
CODEX_ARSCONTEXTA_DIR="$HOME_DIR/.codex/vendor/arscontexta"
CODEX_ARSCONTEXTA_SENTINEL="$HOME_DIR/.codex/.arscontexta-reference-installed"
codex_has_arscontexta_reference() {
  [[ -f "$CODEX_ARSCONTEXTA_DIR/README.md" ]]
}

if command -v codex &>/dev/null; then
  if [[ -f "$CODEX_ARSCONTEXTA_SENTINEL" ]] && ! codex_has_arscontexta_reference; then
    echo "[init]   WARNING: Stale Ars Contexta Codex sentinel detected; reinstalling reference bundle." >&2
    rm -f "$CODEX_ARSCONTEXTA_SENTINEL" 2>/dev/null || true
  fi

  if ! codex_has_arscontexta_reference; then
    echo "[init] Installing Ars Contexta reference bundle for Codex..."
    if [[ -e "$CODEX_ARSCONTEXTA_DIR" ]] && [[ ! -d "$CODEX_ARSCONTEXTA_DIR/.git" ]]; then
      rm -rf "$CODEX_ARSCONTEXTA_DIR" 2>/dev/null || true
    fi
    if [[ ! -d "$CODEX_ARSCONTEXTA_DIR/.git" ]]; then
      mkdir -p "$(dirname "$CODEX_ARSCONTEXTA_DIR")"
      if ! timeout --kill-after=10 30 git clone --depth 1 "$CODEX_ARSCONTEXTA_REPO" "$CODEX_ARSCONTEXTA_DIR" </dev/null; then
        echo "[init]   WARNING: Ars Contexta clone failed or timed out for Codex (non-blocking)" >&2
        rm -rf "$CODEX_ARSCONTEXTA_DIR"
      fi
    fi
  fi

  if codex_has_arscontexta_reference; then
    mkdir -p "$(dirname "$CODEX_ARSCONTEXTA_SENTINEL")"
    touch "$CODEX_ARSCONTEXTA_SENTINEL"
  fi
fi

# bkit (Vibecoding Kit) plugin for Claude Code.
# Installs via marketplace on first run; sentinel prevents repeated installs.
#
# Same pattern as Superpowers above: </dev/null prevents interactive prompts,
# timeout --kill-after sends SIGKILL after grace period, env -u CLAUDECODE
# allows `claude plugin` to work outside a session.
BKIT_SENTINEL="$HOME_DIR/.claude/plugins/.bkit-installed"

# Check if bkit marketplace exists in Claude plugin storage.
claude_has_bkit_marketplace() {
  local marketplace_dir="$HOME_DIR/.claude/plugins/marketplaces/bkit-marketplace"
  [[ -d "$marketplace_dir" ]] && [[ -n "$(ls -A "$marketplace_dir" 2>/dev/null)" ]]
}

# Check if Claude already has bkit installed.
claude_has_bkit_plugin() {
  local plugins_json="$HOME_DIR/.claude/plugins/installed_plugins.json"
  local plugin_cache_dir="$HOME_DIR/.claude/plugins/cache/bkit-marketplace/bkit"

  [[ -f "$plugins_json" ]] \
    && grep -Fq '"bkit@bkit-marketplace"' "$plugins_json" \
    && [[ -d "$plugin_cache_dir" ]] \
    && [[ -n "$(ls -A "$plugin_cache_dir" 2>/dev/null)" ]]
}

if command -v claude &>/dev/null && [[ ! -f "$BKIT_SENTINEL" ]]; then
  if claude_has_bkit_plugin; then
    echo "[init] bkit plugin already present for Claude Code."
    mkdir -p "$(dirname "$BKIT_SENTINEL")"
    touch "$BKIT_SENTINEL"
  else
    echo "[init] Installing bkit plugin for Claude Code..."
    bkit_marketplace_ready=0
    bkit_marketplace_log="$(mktemp)"
    bkit_marketplace_exit=0
    # Source repo is bkit-claude-code; Claude resolves this to marketplace id bkit-marketplace.
    if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin marketplace add popup-studio-ai/bkit-claude-code </dev/null >"$bkit_marketplace_log" 2>&1; then
      bkit_marketplace_exit=$?
    fi

    if claude_has_bkit_marketplace; then
      bkit_marketplace_ready=1
    fi

    if [[ "$bkit_marketplace_ready" -ne 1 ]]; then
      echo "[init]   WARNING: bkit marketplace add failed or timed out (non-blocking)" >&2
      echo "[init]   Exit code: $bkit_marketplace_exit" >&2
      sed 's/^/[init]   /' "$bkit_marketplace_log" >&2 || true
    fi
    rm -f "$bkit_marketplace_log"

    if [[ "$bkit_marketplace_ready" -eq 1 ]]; then
      bkit_install_log="$(mktemp)"
      bkit_install_exit=0
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin install bkit@bkit-marketplace </dev/null >"$bkit_install_log" 2>&1; then
        bkit_install_exit=$?
      fi

      if claude_has_bkit_plugin; then
        mkdir -p "$(dirname "$BKIT_SENTINEL")"
        touch "$BKIT_SENTINEL"
      else
        echo "[init]   WARNING: bkit plugin install failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $bkit_install_exit" >&2
        sed 's/^/[init]   /' "$bkit_install_log" >&2 || true
      fi
      rm -f "$bkit_install_log"
    fi
  fi
fi

# Ars Contexta plugin for Claude Code.
# Installs via marketplace on first run; sentinel prevents repeated installs.
ARSCONTEXTA_SENTINEL="$HOME_DIR/.claude/plugins/.arscontexta-installed"

# Check if Ars Contexta marketplace exists in Claude plugin storage.
claude_has_arscontexta_marketplace() {
  local marketplace_dir="$HOME_DIR/.claude/plugins/marketplaces/agenticnotetaking"
  [[ -d "$marketplace_dir" ]] && [[ -n "$(ls -A "$marketplace_dir" 2>/dev/null)" ]]
}

# Check if Claude already has Ars Contexta installed.
claude_has_arscontexta_plugin() {
  local plugins_json="$HOME_DIR/.claude/plugins/installed_plugins.json"
  local plugin_cache_dir="$HOME_DIR/.claude/plugins/cache/agenticnotetaking/arscontexta"

  [[ -f "$plugins_json" ]] \
    && grep -Fq '"arscontexta@agenticnotetaking"' "$plugins_json" \
    && [[ -d "$plugin_cache_dir" ]] \
    && [[ -n "$(ls -A "$plugin_cache_dir" 2>/dev/null)" ]]
}

if command -v claude &>/dev/null; then
  if [[ -f "$ARSCONTEXTA_SENTINEL" ]] && ! claude_has_arscontexta_plugin; then
    echo "[init]   WARNING: Stale Ars Contexta Claude sentinel detected; reinstalling plugin." >&2
    rm -f "$ARSCONTEXTA_SENTINEL" 2>/dev/null || true
  fi

  if claude_has_arscontexta_plugin; then
    echo "[init] Ars Contexta plugin already present for Claude Code."
    mkdir -p "$(dirname "$ARSCONTEXTA_SENTINEL")"
    touch "$ARSCONTEXTA_SENTINEL"
  else
    echo "[init] Installing Ars Contexta plugin for Claude Code..."
    arscontexta_marketplace_ready=0
    arscontexta_marketplace_log=""
    arscontexta_marketplace_exit=0

    if claude_has_arscontexta_marketplace; then
      arscontexta_marketplace_ready=1
    else
      arscontexta_marketplace_log="$(mktemp)"
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin marketplace add agenticnotetaking/arscontexta </dev/null >"$arscontexta_marketplace_log" 2>&1; then
        arscontexta_marketplace_exit=$?
      fi

      if claude_has_arscontexta_marketplace; then
        arscontexta_marketplace_ready=1
      fi

      if [[ "$arscontexta_marketplace_ready" -ne 1 ]]; then
        echo "[init]   WARNING: Ars Contexta marketplace add failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $arscontexta_marketplace_exit" >&2
        sed 's/^/[init]   /' "$arscontexta_marketplace_log" >&2 || true
      fi
      rm -f "$arscontexta_marketplace_log"
    fi

    if [[ "$arscontexta_marketplace_ready" -eq 1 ]]; then
      arscontexta_install_log="$(mktemp)"
      arscontexta_install_exit=0
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin install --scope user arscontexta@agenticnotetaking </dev/null >"$arscontexta_install_log" 2>&1; then
        arscontexta_install_exit=$?
      fi

      if claude_has_arscontexta_plugin; then
        mkdir -p "$(dirname "$ARSCONTEXTA_SENTINEL")"
        touch "$ARSCONTEXTA_SENTINEL"
      else
        echo "[init]   WARNING: Ars Contexta plugin install failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $arscontexta_install_exit" >&2
        sed 's/^/[init]   /' "$arscontexta_install_log" >&2 || true
      fi
      rm -f "$arscontexta_install_log"
    fi
  fi
fi

# Ensure history file exists for zsh sessions.
touch "$HOME_DIR/.zsh_history"

# ============================================================
# Docker socket access check
# ============================================================
# Warn early if Docker socket is mounted but not accessible.
# This catches the common misconfiguration where --group-add is missing.
if [[ -S /var/run/docker.sock ]]; then
  if timeout --kill-after=3 8 docker version >/dev/null 2>&1; then
    echo "[init] Docker socket: accessible"
  else
    local_sock_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo '?')"
    local_user_groups="$(id -G 2>/dev/null || echo '?')"
    echo "[init] WARNING: Docker socket mounted but not accessible!"
    echo "  Socket GID: $local_sock_gid"
    echo "  Your groups: $local_user_groups"
    echo "  Fix: relaunch with --group-add $local_sock_gid"
    echo "  Or set DOCKER_GID=$local_sock_gid in docker-compose.yml"
  fi
fi

echo "[init] Agent sandbox ready!"
echo ""

# ============================================================
# Execute CMD
# ============================================================
# Hand control to Docker CMD (default: /bin/zsh).
# Using exec keeps correct signal handling and process tree.

# Start a tmux session for Claude Code agent teams support.
# Claude Code teammate mode spawns each teammate as a split pane inside
# the tmux session, so the shell must already be running inside tmux.
# CMD arguments are forwarded as the tmux session shell command so custom
# commands like `docker run agent-sandbox claude` are not silently dropped.
if [[ -z "${TMUX:-}" ]] && command -v tmux &>/dev/null; then
  if exec tmux new-session -s main "$@"; then
    :
  else
    echo "[init] WARNING: tmux session startup failed; falling back to direct command." >&2
  fi
fi
exec "$@"
