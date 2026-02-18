#!/bin/bash
set -euo pipefail

# Build smoke test: verify key tools are present and runnable.
# Run after docker build to catch missing or broken binaries.
#
# Usage:
#   smoke-test.sh              # full test (runtime)
#   smoke-test.sh --build      # skip docker/socket-dependent checks (build time)
#   SMOKE_TEST_SOURCE=repo smoke-test.sh --build  # validate repo files explicitly

FAILED=0
SKIP_DOCKER=false
if [[ "${1:-}" == "--build" ]]; then
  SKIP_DOCKER=true
fi

# Resolve a writable temp root before checks that rely on mktemp.
# Why: some hosts/CI workers mount /tmp with very small quotas.
configure_tmpdir() {
  local candidate
  local probe_dir=""
  local candidates=()

  if [[ -n "${TMPDIR:-}" ]]; then
    candidates+=("$TMPDIR")
  fi
  candidates+=(
    "/tmp"
    "${XDG_RUNTIME_DIR:-}"
    "${HOME:-/home/sandbox}/.cache/agent-sandbox/tmp"
    "$(pwd)/.tmp"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -z "$candidate" ]]; then
      continue
    fi
    if ! mkdir -p "$candidate" >/dev/null 2>&1; then
      continue
    fi
    if probe_dir="$(mktemp -d "$candidate/smoke-test.XXXXXXXXXX" 2>/dev/null)"; then
      rm -rf "$probe_dir"
      export TMPDIR="$candidate"
      return 0
    fi
  done

  echo "  FAIL temp-dir (unable to allocate writable TMPDIR)"
  FAILED=1
  return 1
}

if ! configure_tmpdir; then
  exit 1
fi

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK   $name"
  else
    echo "  FAIL $name ($*)"
    FAILED=1
  fi
}

check_man_entry() {
  local topic="$1"
  if MANPAGER=cat man "$topic" >/dev/null 2>&1; then
    echo "  OK   man:$topic"
  else
    echo "  FAIL man:$topic"
    FAILED=1
  fi
}

extract_shell_function_definition() {
  local script_path="$1"
  local function_name="$2"

  awk -v fn="$function_name" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" {
      in_fn = 1
    }
    in_fn {
      print
      if ($0 ~ "^}[[:space:]]*$") {
        found = 1
        exit 0
      }
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$script_path"
}

resolve_shared_skills_root() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local skills_root="/opt/agent-sandbox/skills"

  case "$source_mode" in
    installed)
      ;;
    repo)
      skills_root="skills"
      ;;
    auto)
      if [[ ! -d "$skills_root" ]] && [[ -d "skills" ]]; then
        # Fallback for local repository runs (outside built container image).
        skills_root="skills"
      fi
      ;;
    *)
      return 1
      ;;
  esac

  echo "$skills_root"
}

resolve_start_script() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        # Fallback for local repository runs (outside built container image).
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      return 1
      ;;
  esac

  echo "$start_script"
}

check_shared_skills_bundle() {
  local skills_root
  if ! skills_root="$(resolve_shared_skills_root)"; then
    echo "  FAIL shared-skills-dir (invalid SMOKE_TEST_SOURCE=${SMOKE_TEST_SOURCE:-auto})"
    FAILED=1
    return
  fi

  if [[ ! -d "$skills_root" ]]; then
    echo "  FAIL shared-skills-dir ($skills_root missing)"
    FAILED=1
    return
  fi

  local skill_dir_count
  local skill_md_count
  skill_dir_count="$(find "$skills_root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  skill_md_count="$(find "$skills_root" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')"

  if [[ "$skill_dir_count" -gt 0 ]]; then
    echo "  OK   shared-skills-bundle (${skill_dir_count} skills)"
  else
    echo "  FAIL shared-skills-bundle (no skills discovered)"
    FAILED=1
  fi

  if [[ "$skill_md_count" -eq "$skill_dir_count" ]]; then
    echo "  OK   shared-skills-structure (every skill has SKILL.md)"
  else
    echo "  FAIL shared-skills-structure (dirs=${skill_dir_count}, skill_md=${skill_md_count})"
    FAILED=1
  fi

  local required_skill="find-skills"
  if [[ -f "$skills_root/$required_skill/SKILL.md" ]]; then
    echo "  OK   shared-skill-required (${required_skill})"
  else
    echo "  FAIL shared-skill-required (${required_skill} missing)"
    FAILED=1
  fi

  local disallowed_skill=""
  local disallowed_found=0
  local disallowed_shared_skills=("pdf" "docx" "pptx" "xlsx")
  for disallowed_skill in "${disallowed_shared_skills[@]}"; do
    if [[ -d "$skills_root/$disallowed_skill" ]]; then
      echo "  FAIL shared-skill-policy (${disallowed_skill} must not be vendored)"
      FAILED=1
      disallowed_found=1
    fi
  done
  if [[ "$disallowed_found" -eq 0 ]]; then
    echo "  OK   shared-skill-policy (no vendored Anthropic proprietary document skills)"
  fi

  local manifest_file="$skills_root/external-manifest.txt"
  local external_targets=()
  if [[ -f "$manifest_file" ]]; then
    mapfile -t external_targets < <(
      awk -F'|' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF == 4 { print $4 }
      ' "$manifest_file"
    )
  fi

  if [[ "${#external_targets[@]}" -eq 0 ]]; then
    echo "  FAIL shared-skill-external-targets (no external targets discovered from manifest)"
    FAILED=1
  else
    local missing_external_count=0
    local broken_symlink_count=0
    local external_target=""
    for external_target in "${external_targets[@]}"; do
      if [[ ! -f "$skills_root/$external_target/SKILL.md" ]]; then
        echo "  FAIL shared-skill-external-target (${external_target} missing)"
        FAILED=1
        missing_external_count=$((missing_external_count + 1))
        continue
      fi

      if find "$skills_root/$external_target" -xtype l -print -quit | grep -q .; then
        echo "  FAIL shared-skill-external-target (${external_target} has broken symlink)"
        FAILED=1
        broken_symlink_count=$((broken_symlink_count + 1))
      fi
    done
    if [[ "$missing_external_count" -eq 0 ]] && [[ "$broken_symlink_count" -eq 0 ]]; then
      echo "  OK   shared-skill-external-targets (${#external_targets[@]} targets)"
    fi
  fi
}

check_shared_skills_metadata() {
  local skills_root
  if ! skills_root="$(resolve_shared_skills_root)"; then
    echo "  FAIL shared-skills-upstream-metadata (invalid SMOKE_TEST_SOURCE=${SMOKE_TEST_SOURCE:-auto})"
    FAILED=1
    return
  fi

  local upstream_file="$skills_root/UPSTREAM.txt"
  if [[ ! -f "$upstream_file" ]]; then
    echo "  FAIL shared-skills-upstream-metadata ($upstream_file missing)"
    FAILED=1
    return
  fi

  if grep -Eq '^commit: [0-9a-f]{40}$' "$upstream_file"; then
    echo "  OK   shared-skills-upstream-metadata"
  else
    echo "  FAIL shared-skills-upstream-metadata (missing valid commit hash)"
    FAILED=1
  fi

  local manifest_file="$skills_root/external-manifest.txt"
  if [[ ! -f "$manifest_file" ]]; then
    echo "  FAIL shared-skills-external-manifest ($manifest_file missing)"
    FAILED=1
    return
  fi

  if awk -F'|' '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
      NF != 4 { bad = 1; next }
      $1 !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/ { bad = 1; next }
      (length($2) != 40) || ($2 !~ /^[0-9a-f]+$/) { bad = 1; next }
      $3 == "" { bad = 1; next }
      $3 ~ /^\// { bad = 1; next }
      $3 ~ /(^|\/)\.\.($|\/)/ { bad = 1; next }
      $3 ~ /\/\// { bad = 1; next }
      $4 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { bad = 1; next }
      ($4 == "pdf") || ($4 == "docx") || ($4 == "pptx") || ($4 == "xlsx") { bad = 1; next }
      seen[$4]++ > 0 { bad = 1; next }
      { count++ }
      END {
        if (count == 0 || bad == 1) {
          exit 1
        }
      }
    ' "$manifest_file"; then
    echo "  OK   shared-skills-external-manifest"
  else
    echo "  FAIL shared-skills-external-manifest (invalid rows or missing pinned refs)"
    FAILED=1
  fi
}

check_shared_skills_install_policy() {
  local start_script
  if ! start_script="$(resolve_start_script)"; then
    echo "  FAIL shared-skills-install-policy (invalid SMOKE_TEST_SOURCE=${SMOKE_TEST_SOURCE:-auto})"
    FAILED=1
    return
  fi

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL shared-skills-install-policy (start.sh not found at $start_script)"
    FAILED=1
    return
  fi

  local codex_ok=0
  local gemini_ok=0
  local claude_ok=0
  local proprietary_exclude_ok=0
  local managed_sync_ok=0
  local managed_all_ok=0
  local managed_hash_sync_ok=0
  local stale_prune_ok=0
  local managed_sync_value=""

  if grep -Fq "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.codex/skills\" \"\$CODEX_SHARED_SKILLS_EXCLUDES\"" "$start_script"; then
    codex_ok=1
  fi
  if grep -Fq "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.gemini/skills\" \"\$GEMINI_SHARED_SKILLS_EXCLUDES\"" "$start_script"; then
    gemini_ok=1
  fi

  local claude_line=""
  claude_line="$(grep -F "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.claude/skills\"" "$start_script" | head -n 1 || true)"
  if [[ "$claude_line" == *'"$CLAUDE_SHARED_SKILLS_EXCLUDES"'* ]]; then
    claude_ok=1
  fi
  if grep -Fq 'PROPRIETARY_SHARED_SKILLS="pdf,docx,pptx,xlsx"' "$start_script" \
    && grep -Fq 'CODEX_SHARED_SKILLS_EXCLUDES="skill-creator,$PROPRIETARY_SHARED_SKILLS"' "$start_script" \
    && grep -Fq 'GEMINI_SHARED_SKILLS_EXCLUDES="skill-creator,$PROPRIETARY_SHARED_SKILLS"' "$start_script"; then
    proprietary_exclude_ok=1
  fi

  managed_sync_value="$(
    grep -E '^[[:space:]]*FORCE_SYNC_SHARED_SKILLS=' "$start_script" \
      | head -n 1 \
      | sed -E 's/^[[:space:]]*FORCE_SYNC_SHARED_SKILLS="?([^"]*)"?/\1/'
    )"

  if [[ -n "$managed_sync_value" ]]; then
    local managed_sync_name
    IFS=',' read -r -a managed_sync_list <<< "$managed_sync_value"
    for managed_sync_name in "${managed_sync_list[@]}"; do
      managed_sync_name="${managed_sync_name//[[:space:]]/}"
      if [[ "$managed_sync_name" == "*" ]]; then
        managed_all_ok=1
      fi
      if [[ "$managed_sync_name" == "playwright-efficient-web-research" ]]; then
        managed_sync_ok=1
      fi
    done
  fi

  if grep -Fq "hash_skill_dir()" "$start_script" \
    && grep -Fq "legacy_adopt_managed_skills" "$start_script" \
    && grep -Fq "managed_bundle_changed" "$start_script"; then
    managed_hash_sync_ok=1
  fi

  if grep -Fq "LEGACY_PRUNED_SHARED_SKILLS=(" "$start_script" \
    && grep -Fq "Removing stale managed shared skill" "$start_script"; then
    stale_prune_ok=1
  fi

  if [[ "$codex_ok" -eq 1 ]] \
    && [[ "$gemini_ok" -eq 1 ]] \
    && [[ "$claude_ok" -eq 1 ]] \
    && [[ "$proprietary_exclude_ok" -eq 1 ]] \
    && [[ "$managed_sync_ok" -eq 1 ]] \
    && [[ "$managed_all_ok" -eq 1 ]] \
    && [[ "$managed_hash_sync_ok" -eq 1 ]] \
    && [[ "$stale_prune_ok" -eq 1 ]]; then
    echo "  OK   shared-skills-install-policy"
  else
    echo "  FAIL shared-skills-install-policy (codex=${codex_ok}, gemini=${gemini_ok}, claude=${claude_ok}, proprietary_exclude=${proprietary_exclude_ok}, managed_sync=${managed_sync_ok}, managed_all=${managed_all_ok}, managed_hash_sync=${managed_hash_sync_ok}, stale_prune=${stale_prune_ok})"
    FAILED=1
  fi
}

check_external_skills_refresh_workflow() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local workflow_path=".github/workflows/update-external-skills.yml"
  local has_schedule=0
  local has_dispatch=0
  local has_vendor_step=0
  local has_smoke_step=0
  local has_pr_step=0

  if [[ "$source_mode" != "repo" ]]; then
    if [[ "$source_mode" == "auto" && -f "$workflow_path" ]]; then
      :
    else
      echo "  OK   external-skills-refresh-workflow (repo-only check skipped)"
      return
    fi
  fi

  if [[ ! -f "$workflow_path" ]]; then
    echo "  FAIL external-skills-refresh-workflow ($workflow_path missing)"
    FAILED=1
    return
  fi

  if grep -Fq "schedule:" "$workflow_path"; then
    has_schedule=1
  fi

  if grep -Fq "workflow_dispatch:" "$workflow_path"; then
    has_dispatch=1
  fi

  if grep -Fq "bash scripts/vendor-external-skills.sh" "$workflow_path"; then
    has_vendor_step=1
  fi

  if grep -Fq "SMOKE_TEST_SOURCE=repo bash scripts/smoke-test.sh --build" "$workflow_path"; then
    has_smoke_step=1
  fi

  if grep -Fq "peter-evans/create-pull-request@" "$workflow_path"; then
    has_pr_step=1
  fi

  if [[ "$has_schedule" -eq 1 ]] \
    && [[ "$has_dispatch" -eq 1 ]] \
    && [[ "$has_vendor_step" -eq 1 ]] \
    && [[ "$has_smoke_step" -eq 1 ]] \
    && [[ "$has_pr_step" -eq 1 ]]; then
    echo "  OK   external-skills-refresh-workflow"
  else
    echo "  FAIL external-skills-refresh-workflow (schedule=${has_schedule}, dispatch=${has_dispatch}, vendor=${has_vendor_step}, smoke=${has_smoke_step}, pr=${has_pr_step})"
    FAILED=1
  fi
}

check_skills_cli_helper_script() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local helper_path="scripts/skills-helper.sh"
  local has_help=0
  local has_check=0
  local has_update=0
  local has_install=0

  if [[ "$source_mode" != "repo" ]]; then
    if [[ "$source_mode" == "auto" && -f "$helper_path" ]]; then
      :
    else
      echo "  OK   skills-cli-helper-script (repo-only check skipped)"
      return
    fi
  fi

  if [[ ! -f "$helper_path" ]]; then
    echo "  FAIL skills-cli-helper-script ($helper_path missing)"
    FAILED=1
    return
  fi

  if grep -Fq "Usage:" "$helper_path"; then
    has_help=1
  fi

  if grep -Fq "skills check" "$helper_path"; then
    has_check=1
  fi

  if grep -Fq "skills update" "$helper_path"; then
    has_update=1
  fi

  if grep -Fq "skills add" "$helper_path"; then
    has_install=1
  fi

  if [[ "$has_help" -eq 1 ]] \
    && [[ "$has_check" -eq 1 ]] \
    && [[ "$has_update" -eq 1 ]] \
    && [[ "$has_install" -eq 1 ]]; then
    echo "  OK   skills-cli-helper-script"
  else
    echo "  FAIL skills-cli-helper-script (help=${has_help}, check=${has_check}, update=${has_update}, install=${has_install})"
    FAILED=1
  fi
}

resolve_templates_root() {
  local templates_root="/etc/skel/.agent-sandbox/templates"
  if [[ ! -d "$templates_root" ]] && [[ -d "configs/templates" ]]; then
    # Fallback for local repository runs (outside built container image).
    templates_root="configs/templates"
  fi
  echo "$templates_root"
}

check_templates_bundle() {
  local templates_root
  templates_root="$(resolve_templates_root)"

  if [[ ! -d "$templates_root" ]]; then
    echo "  FAIL shared-templates-dir ($templates_root missing)"
    FAILED=1
    return
  fi

  local required_files=(
    "prompt-template.md"
    "command-checklist.md"
    "config-snippet.md"
  )

  local missing=0
  local required_file
  for required_file in "${required_files[@]}"; do
    if [[ ! -f "$templates_root/$required_file" ]]; then
      echo "  FAIL shared-templates-file ($required_file missing)"
      FAILED=1
      missing=1
    fi
  done

  local template_count
  template_count="$(find "$templates_root" -type f | wc -l | tr -d ' ')"

  if [[ "$missing" -eq 0 ]] && [[ "$template_count" -ge 3 ]]; then
    echo "  OK   shared-templates-bundle (${template_count} files)"
  elif [[ "$template_count" -lt 3 ]]; then
    echo "  FAIL shared-templates-bundle (expected at least 3 files, got ${template_count})"
    FAILED=1
  fi
}

check_templates_install_policy() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      echo "  FAIL shared-templates-install-policy (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL shared-templates-install-policy ($start_script missing)"
    FAILED=1
    return
  fi

  local has_function=0
  local has_install_call=0

  if grep -Fq "install_default_templates()" "$start_script"; then
    has_function=1
  fi

  if grep -Eq 'install_default_templates[[:space:]]+/etc/skel/.agent-sandbox/templates[[:space:]]+"[$]HOME_DIR/.agent-sandbox/templates"' "$start_script"; then
    has_install_call=1
  fi

  if [[ "$has_function" -eq 1 ]] && [[ "$has_install_call" -eq 1 ]]; then
    echo "  OK   shared-templates-install-policy"
  else
    echo "  FAIL shared-templates-install-policy (function=${has_function}, install_call=${has_install_call})"
    FAILED=1
  fi
}

check_agent_settings_install_policy() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local claude_template="/etc/skel/.claude/settings.json"
  local codex_template="/etc/skel/.codex/settings.json"
  local gemini_template="/etc/skel/.gemini/settings.json"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      claude_template="configs/claude/settings.json"
      codex_template="configs/codex/settings.json"
      gemini_template="configs/gemini/settings.json"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      if [[ ! -f "$claude_template" ]] && [[ -f "configs/claude/settings.json" ]]; then
        claude_template="configs/claude/settings.json"
      fi
      if [[ ! -f "$codex_template" ]] && [[ -f "configs/codex/settings.json" ]]; then
        codex_template="configs/codex/settings.json"
      fi
      if [[ ! -f "$gemini_template" ]] && [[ -f "configs/gemini/settings.json" ]]; then
        gemini_template="configs/gemini/settings.json"
      fi
      ;;
    *)
      echo "  FAIL agent-settings-install-policy (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL agent-settings-install-policy ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$claude_template" ]] || [[ ! -f "$codex_template" ]] || [[ ! -f "$gemini_template" ]]; then
    echo "  FAIL agent-settings-install-policy (missing settings template files)"
    FAILED=1
    return
  fi

  local claude_managed=0
  local codex_managed=0
  local gemini_managed=0
  local runtime_behavior_ok=0

  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.claude/settings.json[[:space:]]+"[$]HOME_DIR/.claude/settings.json"' "$start_script"; then
    claude_managed=1
  fi
  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.codex/settings.json[[:space:]]+"[$]HOME_DIR/.codex/settings.json"' "$start_script"; then
    codex_managed=1
  fi
  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.gemini/settings.json[[:space:]]+"[$]HOME_DIR/.gemini/settings.json"' "$start_script"; then
    gemini_managed=1
  fi

  # Execute update_managed directly against real templates to verify behavior.
  local update_managed_definition
  if update_managed_definition="$(extract_shell_function_definition "$start_script" "update_managed" 2>/dev/null)"; then
    local tmp_root
    tmp_root="$(mktemp -d)"
    runtime_behavior_ok=1

    if ! eval "$update_managed_definition"; then
      runtime_behavior_ok=0
    fi

    if [[ "$runtime_behavior_ok" -eq 1 ]]; then
      local agent template_file missing_dest existing_dest
      for agent in claude codex gemini; do
        case "$agent" in
          claude) template_file="$claude_template" ;;
          codex) template_file="$codex_template" ;;
          gemini) template_file="$gemini_template" ;;
        esac

        missing_dest="$tmp_root/home/.${agent}/missing-settings.json"
        existing_dest="$tmp_root/home/.${agent}/settings.json"

        if ! update_managed "$template_file" "$missing_dest" >/dev/null 2>&1; then
          runtime_behavior_ok=0
          break
        fi
        if ! cmp -s "$template_file" "$missing_dest"; then
          runtime_behavior_ok=0
          break
        fi

        mkdir -p "$(dirname "$existing_dest")"
        printf '{ "user": true }\n' > "$existing_dest"
        if ! update_managed "$template_file" "$existing_dest" >/dev/null 2>&1; then
          runtime_behavior_ok=0
          break
        fi
        if ! cmp -s "$template_file" "$existing_dest"; then
          runtime_behavior_ok=0
          break
        fi
      done
    fi

    rm -rf "$tmp_root"
    unset -f update_managed || true
  fi

  if [[ "$claude_managed" -eq 1 ]] && [[ "$codex_managed" -eq 1 ]] && [[ "$gemini_managed" -eq 1 ]] && [[ "$runtime_behavior_ok" -eq 1 ]]; then
    echo "  OK   agent-settings-install-policy"
  else
    echo "  FAIL agent-settings-install-policy (claude_managed=${claude_managed}, codex_managed=${codex_managed}, gemini_managed=${gemini_managed}, runtime=${runtime_behavior_ok})"
    FAILED=1
  fi
}

resolve_codex_default_check_paths() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local codex_skel_config="/etc/skel/.codex/config.toml"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      codex_skel_config="configs/codex/config.toml"
      ;;
    auto)
      # Prefer installed paths so build/runtime tests validate image contents.
      # Fallback to repository paths only when both installed paths are absent.
      # If one installed path is missing, treat it as a failure signal.
      if [[ ! -f "$start_script" ]] && [[ ! -f "$codex_skel_config" ]]; then
        start_script="scripts/start.sh"
        codex_skel_config="configs/codex/config.toml"
      fi
      ;;
    *)
      echo "  FAIL codex-default-config (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return 1
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL codex-default-config ($start_script missing)"
    FAILED=1
    return 1
  fi

  if [[ ! -f "$codex_skel_config" ]]; then
    echo "  FAIL codex-default-config ($codex_skel_config missing)"
    FAILED=1
    return 1
  fi

  CODEX_DEFAULT_START_SCRIPT="$start_script"
  CODEX_DEFAULT_CONFIG="$codex_skel_config"
}

extract_codex_status_line_items() {
  local config_path="$1"
  awk '
    BEGIN {
      in_tui = 0
      in_status_line = 0
    }
    /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ {
      in_tui = 1
      in_status_line = 0
      next
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
      in_tui = 0
      in_status_line = 0
      next
    }
    in_tui {
      if ($0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
        in_status_line = 1
      }
      if (in_status_line == 1) {
        line = $0
        while (match(line, /"[^"]+"/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          line = substr(line, RSTART + RLENGTH)
        }
        if ($0 ~ /\]/) {
          exit
        }
      }
    }
  ' "$config_path"
}

extract_toml_section_key_value() {
  local config_path="$1"
  local section_name="$2"
  local key_name="$3"

  awk -v section_name="$section_name" -v key_name="$key_name" '
    BEGIN {
      in_section = 0
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
      if ($0 ~ ("^[[:space:]]*\\[" section_name "\\][[:space:]]*(#.*)?$")) {
        in_section = 1
      } else {
        in_section = 0
      }
      next
    }
    in_section && $0 ~ ("^[[:space:]]*" key_name "[[:space:]]*=") {
      line = $0
      sub("^[[:space:]]*" key_name "[[:space:]]*=[[:space:]]*", "", line)
      sub("[[:space:]]*(#.*)?$", "", line)
      print line
      exit
    }
  ' "$config_path"
}

check_codex_default_config() {
  local start_script
  local codex_skel_config
  local expected_items
  local actual_items
  local status_items_ok=1
  local multi_agent_ok=0
  local undo_ok=0
  local apps_ok=0
  local max_threads_ok=0
  local i

  if ! resolve_codex_default_check_paths; then
    return
  fi

  start_script="$CODEX_DEFAULT_START_SCRIPT"
  codex_skel_config="$CODEX_DEFAULT_CONFIG"

  local has_start_hook=0
  local has_multi_agent_merge_hook=0
  local has_undo_merge_hook=0
  local has_apps_merge_hook=0
  local has_max_threads_merge_hook=0

  # shellcheck disable=SC2016
  if grep -Eq 'ensure_codex_status_line[[:space:]]+/etc/skel/.codex/config.toml[[:space:]]+"\$HOME_DIR/.codex/config.toml"' "$start_script"; then
    has_start_hook=1
  fi

  if grep -Fq 'toml_section_has_key "$dest" "features" "multi_agent"' "$start_script" \
    && grep -Fq 'insert_toml_key_into_section "$dest" "features" "multi_agent = true"' "$start_script"; then
    has_multi_agent_merge_hook=1
  fi

  if grep -Fq 'toml_section_has_key "$dest" "features" "undo"' "$start_script" \
    && grep -Fq 'insert_toml_key_into_section "$dest" "features" "undo = true"' "$start_script"; then
    has_undo_merge_hook=1
  fi

  if grep -Fq 'toml_section_has_key "$dest" "features" "apps"' "$start_script" \
    && grep -Fq 'insert_toml_key_into_section "$dest" "features" "apps = true"' "$start_script"; then
    has_apps_merge_hook=1
  fi

  if grep -Fq 'toml_section_has_key "$dest" "agents" "max_threads"' "$start_script" \
    && grep -Fq 'insert_toml_key_into_section "$dest" "agents" "max_threads = 12"' "$start_script"; then
    has_max_threads_merge_hook=1
  fi

  mapfile -t actual_items < <(extract_codex_status_line_items "$codex_skel_config")
  expected_items=(
    "model-with-reasoning"
    "current-dir"
    "git-branch"
    "context-used"
    "total-input-tokens"
    "total-output-tokens"
    "five-hour-limit"
    "weekly-limit"
  )

  if [[ "${#actual_items[@]}" -ne "${#expected_items[@]}" ]]; then
    status_items_ok=0
  else
    for i in "${!expected_items[@]}"; do
      if [[ "${actual_items[$i]}" != "${expected_items[$i]}" ]]; then
        status_items_ok=0
        break
      fi
    done
  fi

  if [[ "$(extract_toml_section_key_value "$codex_skel_config" "features" "multi_agent")" == "true" ]]; then
    multi_agent_ok=1
  fi

  if [[ "$(extract_toml_section_key_value "$codex_skel_config" "features" "undo")" == "true" ]]; then
    undo_ok=1
  fi

  if [[ "$(extract_toml_section_key_value "$codex_skel_config" "features" "apps")" == "true" ]]; then
    apps_ok=1
  fi

  if [[ "$(extract_toml_section_key_value "$codex_skel_config" "agents" "max_threads")" == "12" ]]; then
    max_threads_ok=1
  fi

  if [[ "$has_start_hook" -eq 1 ]] \
    && [[ "$has_multi_agent_merge_hook" -eq 1 ]] \
    && [[ "$has_undo_merge_hook" -eq 1 ]] \
    && [[ "$has_apps_merge_hook" -eq 1 ]] \
    && [[ "$has_max_threads_merge_hook" -eq 1 ]] \
    && [[ "$status_items_ok" -eq 1 ]] \
    && [[ "$multi_agent_ok" -eq 1 ]] \
    && [[ "$undo_ok" -eq 1 ]] \
    && [[ "$apps_ok" -eq 1 ]] \
    && [[ "$max_threads_ok" -eq 1 ]]; then
    echo "  OK   codex-default-config"
  else
    echo "  FAIL codex-default-config (status_items_ok=${status_items_ok}, multi_agent_ok=${multi_agent_ok}, undo_ok=${undo_ok}, apps_ok=${apps_ok}, max_threads_ok=${max_threads_ok}, start_hook=${has_start_hook}, multi_agent_hook=${has_multi_agent_merge_hook}, undo_hook=${has_undo_merge_hook}, apps_hook=${has_apps_merge_hook}, max_threads_hook=${has_max_threads_merge_hook})"
    FAILED=1
  fi
}

resolve_arscontexta_policy_paths() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local codex_bridge_skill="/etc/skel/.codex/skills/arscontexta-bridge/SKILL.md"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      codex_bridge_skill="configs/codex/skills/arscontexta-bridge/SKILL.md"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ ! -f "$codex_bridge_skill" ]]; then
        start_script="scripts/start.sh"
        codex_bridge_skill="configs/codex/skills/arscontexta-bridge/SKILL.md"
      fi
      ;;
    *)
      echo "  FAIL arscontexta-install-policy (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return 1
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL arscontexta-install-policy ($start_script missing)"
    FAILED=1
    return 1
  fi

  if [[ ! -f "$codex_bridge_skill" ]]; then
    echo "  FAIL arscontexta-install-policy ($codex_bridge_skill missing)"
    FAILED=1
    return 1
  fi

  ARSCONTEXTA_POLICY_START_SCRIPT="$start_script"
  ARSCONTEXTA_POLICY_BRIDGE_SKILL="$codex_bridge_skill"
}

check_arscontexta_install_policy() {
  local start_script
  local codex_bridge_skill
  local has_bridge_seed=0
  local has_codex_repo=0
  local has_codex_probe=0
  local has_codex_stale_heal=0
  local has_claude_probe=0
  local has_claude_stale_heal=0
  local has_marketplace_add=0
  local has_marketplace_short_circuit=0
  local has_plugin_install=0
  local bridge_mode_banner=0
  local bridge_command_guard=0

  if ! resolve_arscontexta_policy_paths; then
    return
  fi

  start_script="$ARSCONTEXTA_POLICY_START_SCRIPT"
  codex_bridge_skill="$ARSCONTEXTA_POLICY_BRIDGE_SKILL"

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.codex/skills/arscontexta-bridge/SKILL.md[[:space:]]+"[$]HOME_DIR/.codex/skills/arscontexta-bridge/SKILL.md"' "$start_script"; then
    has_bridge_seed=1
  fi

  if grep -Fq 'CODEX_ARSCONTEXTA_REPO="https://github.com/agenticnotetaking/arscontexta.git"' "$start_script"; then
    has_codex_repo=1
  fi

  if grep -Fq 'codex_has_arscontexta_reference()' "$start_script"; then
    has_codex_probe=1
  fi

  if grep -Fq 'Stale Ars Contexta Codex sentinel detected' "$start_script"; then
    has_codex_stale_heal=1
  fi

  if grep -Fq 'claude_has_arscontexta_plugin()' "$start_script"; then
    has_claude_probe=1
  fi

  if grep -Fq 'Stale Ars Contexta Claude sentinel detected' "$start_script"; then
    has_claude_stale_heal=1
  fi

  if grep -Fq 'claude plugin marketplace add agenticnotetaking/arscontexta' "$start_script"; then
    has_marketplace_add=1
  fi

  if grep -Fq 'if claude_has_arscontexta_marketplace; then' "$start_script"; then
    has_marketplace_short_circuit=1
  fi

  if grep -Fq 'claude plugin install --scope user arscontexta@agenticnotetaking' "$start_script"; then
    has_plugin_install=1
  fi

  if grep -Fq 'manual bridge mode, not Claude plugin mode' "$codex_bridge_skill"; then
    bridge_mode_banner=1
  fi

  if grep -Fq '/arscontexta:setup' "$codex_bridge_skill"; then
    bridge_command_guard=1
  fi

  if [[ "$has_bridge_seed" -eq 1 ]] \
    && [[ "$has_codex_repo" -eq 1 ]] \
    && [[ "$has_codex_probe" -eq 1 ]] \
    && [[ "$has_codex_stale_heal" -eq 1 ]] \
    && [[ "$has_claude_probe" -eq 1 ]] \
    && [[ "$has_claude_stale_heal" -eq 1 ]] \
    && [[ "$has_marketplace_add" -eq 1 ]] \
    && [[ "$has_marketplace_short_circuit" -eq 1 ]] \
    && [[ "$has_plugin_install" -eq 1 ]] \
    && [[ "$bridge_mode_banner" -eq 1 ]] \
    && [[ "$bridge_command_guard" -eq 1 ]]; then
    echo "  OK   arscontexta-install-policy"
  else
    echo "  FAIL arscontexta-install-policy (bridge_seed=${has_bridge_seed}, codex_repo=${has_codex_repo}, codex_probe=${has_codex_probe}, codex_stale_heal=${has_codex_stale_heal}, claude_probe=${has_claude_probe}, claude_stale_heal=${has_claude_stale_heal}, marketplace_add=${has_marketplace_add}, marketplace_short_circuit=${has_marketplace_short_circuit}, plugin_install=${has_plugin_install}, bridge_mode_banner=${bridge_mode_banner}, bridge_command_guard=${bridge_command_guard})"
    FAILED=1
  fi
}

check_tmux_plugin_bootstrap() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local tmux_conf="/etc/skel/.default.tmux.conf"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      tmux_conf="configs/tmux.conf"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ ! -f "$tmux_conf" ]]; then
        start_script="scripts/start.sh"
        tmux_conf="configs/tmux.conf"
      fi
      ;;
    *)
      echo "  FAIL tmux-plugin-bootstrap (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL tmux-plugin-bootstrap ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$tmux_conf" ]]; then
    echo "  FAIL tmux-plugin-bootstrap ($tmux_conf missing)"
    FAILED=1
    return
  fi

  local has_tpm_config=0
  local has_plugin_install=0
  local has_tmux_env_bootstrap=0
  local has_tmux_tmpdir_bootstrap=0
  local has_tmux_start_fallback=0

  if grep -Fq "set -g @plugin 'tmux-plugins/tpm'" "$tmux_conf" \
    && grep -Fq "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$tmux_conf" \
    && grep -Fq "set -g @plugin 'tmux-plugins/tmux-continuum'" "$tmux_conf"; then
    has_tpm_config=1
  fi

  if grep -Fq "install_plugins" "$start_script"; then
    has_plugin_install=1
  fi

  if grep -Fq "tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH" "$start_script"; then
    has_tmux_env_bootstrap=1
  fi

  # shellcheck disable=SC2016
  if grep -Fq 'TMUX_RUNTIME_DIR="$HOME_DIR/.local/state/tmux"' "$start_script" \
    && grep -Fq 'export TMUX_TMPDIR="$TMUX_RUNTIME_DIR"' "$start_script"; then
    has_tmux_tmpdir_bootstrap=1
  fi

  if grep -Fq "tmux session startup failed; falling back to direct command." "$start_script"; then
    has_tmux_start_fallback=1
  fi

  if [[ "$has_tpm_config" -eq 1 ]] \
    && [[ "$has_plugin_install" -eq 1 ]] \
    && [[ "$has_tmux_env_bootstrap" -eq 1 ]] \
    && [[ "$has_tmux_tmpdir_bootstrap" -eq 1 ]] \
    && [[ "$has_tmux_start_fallback" -eq 1 ]]; then
    echo "  OK   tmux-plugin-bootstrap"
  else
    echo "  FAIL tmux-plugin-bootstrap (config=${has_tpm_config}, install=${has_plugin_install}, tmux_env=${has_tmux_env_bootstrap}, tmux_tmpdir=${has_tmux_tmpdir_bootstrap}, tmux_fallback=${has_tmux_start_fallback})"
    FAILED=1
  fi
}

check_tealdeer_update_bootstrap() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      echo "  FAIL tealdeer-update-bootstrap (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL tealdeer-update-bootstrap ($start_script missing)"
    FAILED=1
    return
  fi

  local has_helper=0
  local has_invocation=0
  local runtime_behavior_ok=0

  if grep -Fq "update_tealdeer_cache()" "$start_script"; then
    has_helper=1
  fi

  # Require async invocation so startup does not block on network/update retries.
  if grep -Eq '^[[:space:]]*update_tealdeer_cache[[:space:]]*&[[:space:]]*$' "$start_script"; then
    has_invocation=1
  fi

  # Execute the helper with a stub tldr binary to verify retry + cache cleanup.
  local tealdeer_definition
  if tealdeer_definition="$(extract_shell_function_definition "$start_script" "update_tealdeer_cache" 2>/dev/null)"; then
    local tmp_root
    tmp_root="$(mktemp -d)"
    local stub_bin="$tmp_root/bin"
    local attempt_file="$tmp_root/attempts"
    local custom_cache="$tmp_root/custom-cache"
    local xdg_cache_home="$tmp_root/xdg-cache"
    local xdg_data_home="$tmp_root/xdg-data"

    mkdir -p "$stub_bin" "$custom_cache" "$xdg_cache_home/tealdeer" "$xdg_data_home/tealdeer"
    printf 'cache\n' > "$custom_cache/cache.txt"
    printf 'cache\n' > "$xdg_cache_home/tealdeer/cache.txt"
    printf 'cache\n' > "$xdg_data_home/tealdeer/cache.txt"

    cat > "$stub_bin/tldr" <<'EOF'
#!/bin/bash
set -euo pipefail
attempt_file="${TLDR_TEST_ATTEMPT_FILE:?}"
attempt=0
if [[ -f "$attempt_file" ]]; then
  attempt="$(cat "$attempt_file")"
fi
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
if [[ "$attempt" -eq 1 ]]; then
  echo "InvalidArchive: simulated failure" >&2
  exit 1
fi
echo "updated"
exit 0
EOF
    chmod +x "$stub_bin/tldr"

    if (
      set -euo pipefail
      export PATH="$stub_bin:$PATH"
      export TLDR_TEST_ATTEMPT_FILE="$attempt_file"
      export TLDR_CACHE_DIR="$custom_cache"
      export XDG_CACHE_HOME="$xdg_cache_home"
      export XDG_DATA_HOME="$xdg_data_home"
      export HOME_DIR="$tmp_root/home"
      eval "$tealdeer_definition"
      update_tealdeer_cache >/dev/null 2>&1
    ); then
      if [[ -f "$attempt_file" ]] && [[ "$(cat "$attempt_file")" == "2" ]] \
        && [[ ! -d "$custom_cache" ]] \
        && [[ ! -d "$xdg_cache_home/tealdeer" ]] \
        && [[ ! -d "$xdg_data_home/tealdeer" ]]; then
        runtime_behavior_ok=1
      fi
    fi

    rm -rf "$tmp_root"
  fi

  if [[ "$has_helper" -eq 1 ]] && [[ "$has_invocation" -eq 1 ]] && [[ "$runtime_behavior_ok" -eq 1 ]]; then
    echo "  OK   tealdeer-update-bootstrap"
  else
    echo "  FAIL tealdeer-update-bootstrap (helper=${has_helper}, invocation=${has_invocation}, runtime=${runtime_behavior_ok})"
    FAILED=1
  fi
}

check_editor_defaults() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local vim_config="/etc/skel/.default.vimrc"
  local nvim_config="/etc/skel/.config/nvim/init.lua"
  local micro_settings_config="/etc/skel/.config/micro/settings.json"
  local micro_bindings_config="/etc/skel/.config/micro/bindings.json"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      vim_config="configs/vimrc"
      nvim_config="configs/nvim/init.lua"
      micro_settings_config="configs/micro/settings.json"
      micro_bindings_config="configs/micro/bindings.json"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ ! -f "$vim_config" ]] && [[ ! -f "$nvim_config" ]] && [[ ! -f "$micro_settings_config" ]] && [[ ! -f "$micro_bindings_config" ]]; then
        start_script="scripts/start.sh"
        vim_config="configs/vimrc"
        nvim_config="configs/nvim/init.lua"
        micro_settings_config="configs/micro/settings.json"
        micro_bindings_config="configs/micro/bindings.json"
      fi
      ;;
    *)
      echo "  FAIL editor-default-config (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL editor-default-config ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$vim_config" ]]; then
    echo "  FAIL editor-default-config ($vim_config missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$nvim_config" ]]; then
    echo "  FAIL editor-default-config ($nvim_config missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$micro_settings_config" ]]; then
    echo "  FAIL editor-default-config ($micro_settings_config missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$micro_bindings_config" ]]; then
    echo "  FAIL editor-default-config ($micro_bindings_config missing)"
    FAILED=1
    return
  fi

  local has_vim_hook=0
  local has_nvim_hook=0
  local has_micro_settings_hook=0
  local has_micro_bindings_hook=0
  local has_micro_plugin_bootstrap=0

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.default.vimrc[[:space:]]+"[$]HOME_DIR/.vimrc"' "$start_script"; then
    has_vim_hook=1
  fi

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.config/nvim/init.lua[[:space:]]+"[$]HOME_DIR/.config/nvim/init.lua"' "$start_script"; then
    has_nvim_hook=1
  fi

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.config/micro/settings.json[[:space:]]+"[$]HOME_DIR/.config/micro/settings.json"' "$start_script"; then
    has_micro_settings_hook=1
  fi

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.config/micro/bindings.json[[:space:]]+"[$]HOME_DIR/.config/micro/bindings.json"' "$start_script"; then
    has_micro_bindings_hook=1
  fi

  if grep -Eq '^install_micro_plugins\(\)' "$start_script" \
    && grep -Eq '^[[:space:]]*install_micro_plugins[[:space:]]*$' "$start_script" \
    && grep -Eq 'detectindent|fzf|lsp' "$start_script"; then
    has_micro_plugin_bootstrap=1
  fi

  if [[ "$has_vim_hook" -eq 1 ]] && [[ "$has_nvim_hook" -eq 1 ]] && [[ "$has_micro_settings_hook" -eq 1 ]] && [[ "$has_micro_bindings_hook" -eq 1 ]] && [[ "$has_micro_plugin_bootstrap" -eq 1 ]]; then
    echo "  OK   editor-default-config"
  else
    echo "  FAIL editor-default-config (vim_hook=${has_vim_hook}, nvim_hook=${has_nvim_hook}, micro_settings_hook=${has_micro_settings_hook}, micro_bindings_hook=${has_micro_bindings_hook}, micro_plugin_bootstrap=${has_micro_plugin_bootstrap})"
    FAILED=1
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

check_playwright_chromium_companion() {
  local browsers_root="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
  local chromium_bin=""
  local probe_session="smoke-playwright-$$"
  local probe_tmpdir="${TMPDIR:-/tmp}"
  local probe_dir=""
  local probe_home=""
  local probe_cache=""

  if ! chromium_bin="$(find_playwright_chromium_binary "$browsers_root")"; then
    echo "  FAIL playwright-chromium-companion (missing chromium binary under ${browsers_root})"
    FAILED=1
    return
  fi

  if [[ ! -x "$chromium_bin" ]]; then
    echo "  FAIL playwright-chromium-companion (binary not executable: ${chromium_bin})"
    FAILED=1
    return
  fi

  if ! "$chromium_bin" --version >/dev/null 2>&1; then
    echo "  FAIL playwright-chromium-companion (binary --version failed: ${chromium_bin})"
    FAILED=1
    return
  fi

  if ! probe_dir="$(mktemp -d "$probe_tmpdir/playwright-smoke-probe.XXXXXXXXXX" 2>/dev/null)"; then
    echo "  FAIL playwright-chromium-companion (cannot allocate probe directory)"
    FAILED=1
    return
  fi

  probe_home="$probe_dir/home"
  probe_cache="$probe_dir/cache"
  if ! mkdir -p "$probe_home" "$probe_cache" 2>/dev/null; then
    rm -rf "$probe_dir"
    echo "  FAIL playwright-chromium-companion (cannot prepare probe cache directories)"
    FAILED=1
    return
  fi

  if (
    cd "$probe_dir"
    timeout --kill-after=10 45 env TMPDIR="$probe_tmpdir" HOME="$probe_home" XDG_CACHE_HOME="$probe_cache" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
      playwright-cli -s="$probe_session" open about:blank --browser=chromium >/dev/null 2>&1
  ); then
    (
      cd "$probe_dir"
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" HOME="$probe_home" XDG_CACHE_HOME="$probe_cache" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" close >/dev/null 2>&1 || true
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" HOME="$probe_home" XDG_CACHE_HOME="$probe_cache" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" delete-data >/dev/null 2>&1 || true
    )
    rm -rf "$probe_dir"
    echo "  OK   playwright-chromium-companion"
  else
    (
      cd "$probe_dir"
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" HOME="$probe_home" XDG_CACHE_HOME="$probe_cache" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" close >/dev/null 2>&1 || true
      timeout --kill-after=10 20 env TMPDIR="$probe_tmpdir" HOME="$probe_home" XDG_CACHE_HOME="$probe_cache" PLAYWRIGHT_BROWSERS_PATH="$browsers_root" \
        playwright-cli -s="$probe_session" delete-data >/dev/null 2>&1 || true
    )
    rm -rf "$probe_dir"
    echo "  FAIL playwright-chromium-companion (playwright open/close probe failed)"
    FAILED=1
  fi
}

check_playwright_runtime_bootstrap_policy() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      echo "  FAIL playwright-runtime-bootstrap (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL playwright-runtime-bootstrap ($start_script missing)"
    FAILED=1
    return
  fi

  local has_helper=0
  local has_invocation=0
  local has_fallback_path=0
  local has_install_call=0
  local has_locking=0
  local has_isolated_bootstrap=0
  local has_fail_closed=0
  local has_writable_fallback=0
  local has_payload_only_dedupe=0
  local runtime_behavior_ok=0

  if grep -Eq '^ensure_playwright_chromium\(\)' "$start_script"; then
    has_helper=1
  fi

  if grep -Eq '^[[:space:]]*ensure_playwright_chromium[[:space:]]*$' "$start_script"; then
    has_invocation=1
  fi

  if grep -Fq '.cache/ms-playwright' "$start_script" \
    || grep -Fq 'XDG_CACHE_HOME:-$HOME_DIR/.cache}/ms-playwright' "$start_script"; then
    has_fallback_path=1
  fi

  if grep -Fq 'playwright/cli.js' "$start_script" && grep -Fq 'install chromium' "$start_script"; then
    has_install_call=1
  fi
  if grep -Fq 'playwright-cli install' "$start_script"; then
    has_install_call=1
  fi

  if grep -Fq 'flock -w' "$start_script"; then
    has_locking=1
  fi

  if grep -Fq 'playwright-bootstrap.' "$start_script"; then
    has_isolated_bootstrap=1
  fi

  if grep -Fq 'Playwright Chromium companion bootstrap failed' "$start_script"; then
    has_fail_closed=1
  fi
  if grep -Fq 'prepare_playwright_install_root' "$start_script" \
    && grep -Fq 'fallback cache root is not writable' "$start_script"; then
    has_writable_fallback=1
  fi
  if grep -Fq 'Deduplicated Playwright fallback payload directories' "$start_script" \
    && ! grep -Fq 'ln -s "$canonical_root" "$duplicate_root"' "$start_script"; then
    has_payload_only_dedupe=1
  fi

  local find_playwright_definition
  local playwright_definition
  if find_playwright_definition="$(extract_shell_function_definition "$start_script" "find_playwright_chromium_binary" 2>/dev/null)" \
    && playwright_definition="$(extract_shell_function_definition "$start_script" "ensure_playwright_chromium" 2>/dev/null)"; then
    local tmp_root
    tmp_root="$(mktemp -d)"
    local stub_bin="$tmp_root/bin"
    mkdir -p "$stub_bin"

    cat > "$stub_bin/playwright-cli" <<'EOF'
#!/bin/bash
set -euo pipefail
cmd="${1:-}"
case "$cmd" in
  open|close|delete-data|--version)
    ;;
  *)
    ;;
esac
exit 0
EOF
    chmod +x "$stub_bin/playwright-cli"

    cat > "$stub_bin/npm" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "root" && "${2:-}" == "-g" ]]; then
  echo "${PLAYWRIGHT_TEST_NPM_ROOT:?}"
  exit 0
fi
exit 0
EOF
    chmod +x "$stub_bin/npm"

    cat > "$stub_bin/node" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == *"/@playwright/cli/node_modules/playwright/cli.js" ]] \
  && [[ "${2:-}" == "install" ]] \
  && [[ "${3:-}" == "chromium" ]]; then
  if [[ "${PLAYWRIGHT_TEST_FORCE_INSTALL_FAIL:-0}" == "1" ]]; then
    echo "forced install failure" >&2
    exit 1
  fi
  target_root="${PLAYWRIGHT_BROWSERS_PATH:?}"
  mkdir -p "$target_root/chromium-9999/chrome-linux"
  cat > "$target_root/chromium-9999/chrome-linux/chrome" <<'INNER'
#!/bin/bash
echo "Chromium 9999.0"
INNER
  chmod +x "$target_root/chromium-9999/chrome-linux/chrome"
  touch "$target_root/chromium-9999/INSTALLATION_COMPLETE"
  exit 0
fi
exit 0
EOF
    chmod +x "$stub_bin/node"

    mkdir -p "$tmp_root/npm-root/@playwright/cli/node_modules/playwright"
    touch "$tmp_root/npm-root/@playwright/cli/node_modules/playwright/cli.js"

    local runtime_basic_ok=0
    local runtime_fail_closed_ok=0
    local runtime_symlink_repair_ok=0
    local runtime_zsh_ok=0

    if (
      set -euo pipefail
      export PATH="$stub_bin:$PATH"
      export HOME_DIR="$tmp_root/home"
      export XDG_CACHE_HOME="$tmp_root/xdg-cache"
      export PLAYWRIGHT_BROWSERS_PATH="$tmp_root/primary"
      export PLAYWRIGHT_TEST_NPM_ROOT="$tmp_root/npm-root"
      eval "$find_playwright_definition"
      eval "$playwright_definition"
      ensure_playwright_chromium >/dev/null 2>&1
      [[ "$PLAYWRIGHT_BROWSERS_PATH" == "$tmp_root/xdg-cache/ms-playwright" ]]
    ); then
      runtime_basic_ok=1
      if (
        set -euo pipefail
        export PATH="$stub_bin:$PATH"
        export HOME_DIR="$tmp_root/home-fail"
        export XDG_CACHE_HOME="$tmp_root/xdg-cache-fail"
        export PLAYWRIGHT_BROWSERS_PATH="$tmp_root/primary-fail"
        export PLAYWRIGHT_TEST_NPM_ROOT="$tmp_root/npm-root"
        export PLAYWRIGHT_TEST_FORCE_INSTALL_FAIL=1
        eval "$find_playwright_definition"
        eval "$playwright_definition"
        ensure_playwright_chromium >/dev/null 2>&1
      ); then
        runtime_fail_closed_ok=0
      else
        runtime_fail_closed_ok=1
      fi
    fi

    if (
      set -euo pipefail
      export PATH="$stub_bin:$PATH"
      export HOME_DIR="$tmp_root/home-link"
      export XDG_CACHE_HOME="$tmp_root/xdg-cache-link"
      export PLAYWRIGHT_BROWSERS_PATH="$tmp_root/primary-link"
      export PLAYWRIGHT_TEST_NPM_ROOT="$tmp_root/npm-root"
      mkdir -p "$tmp_root/readonly-target" "$tmp_root/xdg-cache-link"
      chmod 0555 "$tmp_root/readonly-target"
      ln -s "$tmp_root/readonly-target" "$tmp_root/xdg-cache-link/ms-playwright"
      eval "$find_playwright_definition"
      eval "$playwright_definition"
      ensure_playwright_chromium >/dev/null 2>&1
      [[ ! -L "$tmp_root/xdg-cache-link/ms-playwright" ]]
      candidate_bin="$(find_playwright_chromium_binary "$tmp_root/xdg-cache-link/ms-playwright")"
      [[ -n "$candidate_bin" ]]
      [[ -x "$candidate_bin" ]]
    ); then
      runtime_symlink_repair_ok=1
    fi

    if command -v zsh &>/dev/null; then
      if (
        set -euo pipefail
        local zsh_runtime_script="$tmp_root/playwright-runtime-zsh-check.zsh"
        export PATH="$stub_bin:$PATH"
        export HOME_DIR="$tmp_root/home-zsh"
        export XDG_CACHE_HOME="$tmp_root/xdg-cache-zsh"
        export PLAYWRIGHT_BROWSERS_PATH="$tmp_root/primary-zsh"
        export PLAYWRIGHT_TEST_NPM_ROOT="$tmp_root/npm-root"
        mkdir -p "$tmp_root/readonly-target-zsh" "$tmp_root/xdg-cache-zsh"
        chmod 0555 "$tmp_root/readonly-target-zsh"
        ln -s "$tmp_root/readonly-target-zsh" "$tmp_root/xdg-cache-zsh/ms-playwright"
        {
          printf '%s\n' 'set -euo pipefail'
          printf '%s\n' "$find_playwright_definition"
          printf '%s\n' "$playwright_definition"
          printf '%s\n' 'ensure_playwright_chromium >/dev/null 2>&1'
          printf '%s\n' '[[ ! -L "$XDG_CACHE_HOME/ms-playwright" ]]'
          printf '%s\n' 'candidate_bin="$(find_playwright_chromium_binary "$XDG_CACHE_HOME/ms-playwright")"'
          printf '%s\n' '[[ -n "$candidate_bin" ]]'
          printf '%s\n' '[[ -x "$candidate_bin" ]]'
        } > "$zsh_runtime_script"
        zsh "$zsh_runtime_script" >/dev/null 2>&1
      ); then
        runtime_zsh_ok=1
      fi
    else
      runtime_zsh_ok=1
    fi

    if [[ "$runtime_basic_ok" -eq 1 ]] \
      && [[ "$runtime_fail_closed_ok" -eq 1 ]] \
      && [[ "$runtime_symlink_repair_ok" -eq 1 ]] \
      && [[ "$runtime_zsh_ok" -eq 1 ]]; then
      runtime_behavior_ok=1
    fi

    rm -rf "$tmp_root"
  fi

  if [[ "$has_helper" -eq 1 ]] \
    && [[ "$has_invocation" -eq 1 ]] \
    && [[ "$has_fallback_path" -eq 1 ]] \
    && [[ "$has_install_call" -eq 1 ]] \
    && [[ "$has_locking" -eq 1 ]] \
    && [[ "$has_isolated_bootstrap" -eq 1 ]] \
    && [[ "$has_fail_closed" -eq 1 ]] \
    && [[ "$has_writable_fallback" -eq 1 ]] \
    && [[ "$has_payload_only_dedupe" -eq 1 ]] \
    && [[ "$runtime_behavior_ok" -eq 1 ]]; then
    echo "  OK   playwright-runtime-bootstrap"
  else
    echo "  FAIL playwright-runtime-bootstrap (helper=${has_helper}, invocation=${has_invocation}, fallback=${has_fallback_path}, install=${has_install_call}, lock=${has_locking}, isolated=${has_isolated_bootstrap}, fail_closed=${has_fail_closed}, writable_fallback=${has_writable_fallback}, payload_only_dedupe=${has_payload_only_dedupe}, runtime=${runtime_behavior_ok})"
    FAILED=1
  fi
}

echo "=== Agent Sandbox Smoke Test ==="
echo ""
echo "--- Coding Agents ---"
check "claude"    claude --version
check "codex"     codex --version
check "gemini"    gemini --version
check "opencode"  opencode --version

echo ""
echo "--- Agent Productivity Tools ---"
check "beads"     bd --version

echo ""
echo "--- Shared Skills ---"
check_shared_skills_bundle
check_shared_skills_metadata
check_shared_skills_install_policy
check_external_skills_refresh_workflow
check_skills_cli_helper_script

echo ""
echo "--- Shared Templates ---"
check_templates_bundle
check_templates_install_policy

echo ""
echo "--- Agent Defaults ---"
check_agent_settings_install_policy
check_codex_default_config
check_arscontexta_install_policy
check_tmux_plugin_bootstrap
check_tealdeer_update_bootstrap
check_editor_defaults
check_playwright_runtime_bootstrap_policy

echo ""
echo "--- Core Tools ---"
check "git"       git --version
if [[ "$SKIP_DOCKER" == false ]]; then
  check "docker"  docker --version
fi
check "gh"        gh --version
check "node"      node --version
check "bun"       bun --version
check "python3"   python3 --version
check "uv"        uv --version
check "playwright-cli" playwright-cli --version
check_playwright_chromium_companion
check "vim"       vim --version
check "nvim"      nvim --version

echo ""
echo "--- Shell Tools ---"
check "bat"       bat --version
check "eza"       eza --version
check "fd"        fd --version
check "fzf"       fzf --version
check "rg"        rg --version
check "dust"      dust --version
check "procs"     procs --version
check "btm"       btm --version
check "xh"        xh --version
check "mcfly"     mcfly --version
check "zoxide"    zoxide --version
check "tldr"      tldr --version
check "starship"  starship --version
check "micro"     micro --version
check "delta"     delta --version
check "lazygit"   lazygit --version
check "gitui"     gitui --version
check "tokei"     tokei --version
check "yq"        yq --version
check "jq"        jq --version
check "tmux"      tmux -V
check "direnv"    direnv version

echo ""
echo "--- Security/Quality Tools ---"
check "pre-commit"  pre-commit --version
check "gitleaks"    gitleaks version
check "hadolint"    hadolint --version
check "shellcheck"  shellcheck --version
check "actionlint"  actionlint --version
check "trivy"       trivy --version
check "yamllint"    yamllint --version

echo ""
echo "--- Manual Pages ---"
check_man_entry "curl"
check_man_entry "zsh"
check_man_entry "htop"
check_man_entry "nnn"
check_man_entry "ncdu"
check_man_entry "jq"
check_man_entry "rg"
check_man_entry "bat"
check_man_entry "zoxide"
check_man_entry "shellcheck"
check_man_entry "uv"
check_man_entry "uvx"

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed!"
else
  echo "Some checks FAILED. See above."
  exit 1
fi
