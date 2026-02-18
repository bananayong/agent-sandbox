#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_ROOT="$REPO_ROOT/skills"
UPSTREAM_FILE="$SKILLS_ROOT/UPSTREAM.txt"
MANIFEST_FILE="$SKILLS_ROOT/external-manifest.txt"
BEGIN_MARKER="# BEGIN external-skill-sources (managed by scripts/vendor-external-skills.sh)"
END_MARKER="# END external-skill-sources (managed by scripts/vendor-external-skills.sh)"
DISALLOWED_TARGET_SKILLS=("pdf" "docx" "pptx" "xlsx")

if [[ ! -d "$SKILLS_ROOT" ]]; then
  echo "[error] skills directory not found: $SKILLS_ROOT" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "[error] external manifest not found: $MANIFEST_FILE" >&2
  exit 1
fi

# Mapping format: repo|source_path|target_skill_name
# Repo refs are loaded from manifest (repo|ref|source_path|target).
declare -a MAPPINGS=()
declare -A repo_ref_map=()
declare -A repo_dir_map=()
declare -A repo_sha_map=()
declare -A target_seen=()
declare -A previous_external_targets=()

is_valid_repo_slug() {
  local repo="$1"
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]
}

is_safe_target_name() {
  local target="$1"
  [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

is_safe_source_path() {
  local path="$1"
  [[ -n "$path" ]] || return 1
  [[ "$path" != /* ]] || return 1
  [[ "$path" != *'//'* ]] || return 1
  [[ ! "$path" =~ (^|/)\.\.(/|$) ]] || return 1
  return 0
}

is_disallowed_target_skill() {
  local target="$1"
  local disallowed=""
  for disallowed in "${DISALLOWED_TARGET_SKILLS[@]}"; do
    if [[ "$target" == "$disallowed" ]]; then
      return 0
    fi
  done
  return 1
}

assert_no_disallowed_vendored_skills() {
  local disallowed=""
  local found=0
  for disallowed in "${DISALLOWED_TARGET_SKILLS[@]}"; do
    if [[ -d "$SKILLS_ROOT/$disallowed" ]]; then
      echo "[error] disallowed vendored skill directory detected: $SKILLS_ROOT/$disallowed" >&2
      found=1
    fi
  done

  if [[ "$found" -eq 1 ]]; then
    echo "[error] Anthropic proprietary document skills must not be vendored in this repo." >&2
    echo "[error] Install via official marketplace instead:" >&2
    echo "[error]   claude plugin marketplace add anthropics/skills" >&2
    echo "[error]   claude plugin install --scope user document-skills@anthropic-agent-skills" >&2
    exit 1
  fi
}

load_manifest() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    local repo=""
    local ref=""
    local source_path=""
    local target_name=""
    local extra=""

    IFS='|' read -r repo ref source_path target_name extra <<< "$line"
    if [[ -n "$extra" || -z "$repo" || -z "$ref" || -z "$source_path" || -z "$target_name" ]]; then
      echo "[error] invalid manifest row: $line" >&2
      exit 1
    fi

    if ! is_valid_repo_slug "$repo"; then
      echo "[error] invalid repo slug in manifest: $repo" >&2
      exit 1
    fi
    if ! is_safe_source_path "$source_path"; then
      echo "[error] unsafe source path in manifest: $source_path" >&2
      exit 1
    fi
    if ! is_safe_target_name "$target_name"; then
      echo "[error] unsafe target name in manifest: $target_name" >&2
      exit 1
    fi
    if is_disallowed_target_skill "$target_name"; then
      echo "[error] manifest includes disallowed proprietary skill target: $target_name" >&2
      echo "[error] keep this target out of repo vendoring and use official marketplace install." >&2
      exit 1
    fi
    if [[ ! "$ref" =~ ^[0-9a-f]{40}$ ]] && [[ ! "$ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
      echo "[error] invalid ref in manifest: $ref" >&2
      exit 1
    fi

    if [[ -n "${target_seen[$target_name]:-}" ]]; then
      echo "[error] duplicate target skill name in manifest: $target_name" >&2
      exit 1
    fi
    target_seen[$target_name]=1

    if [[ -n "${repo_ref_map[$repo]:-}" && "${repo_ref_map[$repo]}" != "$ref" ]]; then
      echo "[error] repo ref conflict in manifest for $repo (${repo_ref_map[$repo]} vs $ref)" >&2
      exit 1
    fi

    repo_ref_map[$repo]="$ref"
    MAPPINGS+=("$repo|$source_path|$target_name")
  done < "$MANIFEST_FILE"

  if [[ "${#MAPPINGS[@]}" -eq 0 ]]; then
    echo "[error] no external mappings loaded from manifest" >&2
    exit 1
  fi
}

load_previous_targets() {
  if [[ ! -f "$UPSTREAM_FILE" ]]; then
    return
  fi

  local target
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    previous_external_targets[$target]=1
  done < <(
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin { in_block = 1; next }
      $0 == end { in_block = 0; next }
      in_block && $0 ~ /^#   target: / {
        sub(/^#   target: /, "", $0)
        print $0
      }
    ' "$UPSTREAM_FILE"
  )
}

clone_repos() {
  local repo
  for repo in "${!repo_ref_map[@]}"; do
    local ref="${repo_ref_map[$repo]}"
    local repo_dir
    repo_dir="$TMP_DIR/${repo//\//__}"

    echo "[clone] https://github.com/$repo.git @ $ref"

    if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
      git clone "https://github.com/$repo.git" "$repo_dir" >/dev/null
      git -C "$repo_dir" checkout --quiet "$ref"
    else
      git clone --depth 1 --branch "$ref" "https://github.com/$repo.git" "$repo_dir" >/dev/null
    fi

    repo_dir_map[$repo]="$repo_dir"
    repo_sha_map[$repo]="$(git -C "$repo_dir" rev-parse HEAD)"
  done
}

sync_skills() {
  local mapping
  for mapping in "${MAPPINGS[@]}"; do
    local repo=""
    local source_path=""
    local target_name=""

    IFS='|' read -r repo source_path target_name <<< "$mapping"

    local source_dir="${repo_dir_map[$repo]}/$source_path"
    local source_skill_md="$source_dir/SKILL.md"
    local target_dir="$SKILLS_ROOT/$target_name"

    if [[ ! -f "$source_skill_md" ]]; then
      echo "[error] missing SKILL.md: $repo/$source_path" >&2
      exit 1
    fi

    echo "[sync] $target_name <= $repo/$source_path"
    rm -rf "$target_dir"
    # Follow symlinks so vendored skills remain self-contained in this repo.
    cp -RL "$source_dir" "$target_dir"
  done
}

prune_stale_external_skills() {
  local old_target
  for old_target in "${!previous_external_targets[@]}"; do
    if ! is_safe_target_name "$old_target"; then
      echo "[warn] skipping unsafe stale target from UPSTREAM metadata: $old_target" >&2
      continue
    fi

    if [[ -n "${target_seen[$old_target]:-}" ]]; then
      continue
    fi

    local stale_dir="$SKILLS_ROOT/$old_target"
    if [[ -d "$stale_dir" ]]; then
      echo "[prune] removing stale external skill: $old_target"
      rm -rf "${stale_dir:?}"
    fi
  done
}

verify_synced_targets() {
  local mapping
  for mapping in "${MAPPINGS[@]}"; do
    local _repo=""
    local _source_path=""
    local target_name=""

    IFS='|' read -r _repo _source_path target_name <<< "$mapping"
    if [[ ! -f "$SKILLS_ROOT/$target_name/SKILL.md" ]]; then
      echo "[error] post-sync skill missing SKILL.md: $target_name" >&2
      exit 1
    fi
  done
}

update_upstream_metadata() {
  local metadata_block="$TMP_DIR/external-upstream-block.txt"
  local timestamp_utc
  timestamp_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  {
    echo "$BEGIN_MARKER"
    echo "# generated_at_utc: $timestamp_utc"

    local mapping
    for mapping in "${MAPPINGS[@]}"; do
      local repo=""
      local source_path=""
      local target_name=""
      local ref=""

      IFS='|' read -r repo source_path target_name <<< "$mapping"
      ref="${repo_ref_map[$repo]}"

      echo "# - repository: https://github.com/$repo"
      echo "#   ref: $ref"
      echo "#   path: $source_path"
      echo "#   target: $target_name"
      echo "#   commit: ${repo_sha_map[$repo]}"
    done

    echo "$END_MARKER"
  } > "$metadata_block"

  if [[ ! -f "$UPSTREAM_FILE" ]]; then
    cp "$metadata_block" "$UPSTREAM_FILE"
    return
  fi

  local updated_upstream="$TMP_DIR/UPSTREAM.txt"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v block_file="$metadata_block" '
    function emit_block(    line) {
      while ((getline line < block_file) > 0) {
        print line
      }
      close(block_file)
    }
    $0 == begin {
      emit_block()
      in_block = 1
      replaced = 1
      next
    }
    $0 == end {
      in_block = 0
      next
    }
    !in_block {
      print
    }
    END {
      if (!replaced) {
        if (NR > 0) {
          print ""
        }
        emit_block()
      }
    }
  ' "$UPSTREAM_FILE" > "$updated_upstream"

  mv "$updated_upstream" "$UPSTREAM_FILE"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

load_manifest
assert_no_disallowed_vendored_skills
load_previous_targets
clone_repos
sync_skills
prune_stale_external_skills
verify_synced_targets
assert_no_disallowed_vendored_skills
update_upstream_metadata

echo "[done] synced ${#MAPPINGS[@]} external skills into $SKILLS_ROOT"
