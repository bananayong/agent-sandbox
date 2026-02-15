#!/bin/bash
set -euo pipefail

# Version maintenance helper for this repository.
#
# What this script does:
# 1) Scans pinned versions in Dockerfile and GitHub workflows
# 2) Checks upstream latest versions/SHAs
# 3) Optionally updates local files in-place
#
# Safety notes:
# - It only edits pinned version fields (ARG lines, uses@SHA, codex npm pin).
# - It does not create commits or push changes.
# - Network/API calls are read-only (GitHub API + npm registry).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOCKERFILE="${REPO_ROOT}/Dockerfile"

MODE="check"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  scripts/update-versions.sh [scan|check|update] [--dry-run]

Modes:
  scan    Print currently pinned versions (no network)
  check   Compare pinned versions with upstream latest (default)
  update  Update pinned versions to upstream latest

Options:
  --dry-run  Show what would change without editing files
  -h, --help Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    scan|check|update)
      MODE="$arg"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${DOCKERFILE}" ]]; then
  echo "Dockerfile not found: ${DOCKERFILE}" >&2
  exit 1
fi

mapfile -t WORKFLOW_FILES < <(find "${REPO_ROOT}/.github/workflows" -maxdepth 1 -type f -name '*.yml' | sort)
if [[ "${#WORKFLOW_FILES[@]}" -eq 0 ]]; then
  echo "No workflow files found under .github/workflows" >&2
  exit 1
fi

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

extract_version() {
  local raw="$1"
  if [[ "${raw}" =~ ([0-9]+([.][0-9]+)+([-.][0-9A-Za-z]+)?) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

docker_arg_value() {
  local arg_name="$1"
  awk -F= -v key="${arg_name}" '$0 ~ "^ARG "key"=" { print $2; exit }' "${DOCKERFILE}"
}

set_docker_arg_value() {
  local arg_name="$1"
  local new_value="$2"
  sed -i -E "s|^ARG ${arg_name}=.*$|ARG ${arg_name}=${new_value}|" "${DOCKERFILE}"
}

latest_release_version() {
  local repo="$1"
  local tag=""
  local parsed=""

  tag="$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    tag="$(gh api "repos/${repo}/tags" --jq '.[0].name' 2>/dev/null || true)"
  fi
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    return 1
  fi

  parsed="$(extract_version "${tag}")"
  if [[ -z "${parsed}" ]]; then
    return 1
  fi

  echo "${parsed}"
}

latest_action_sha_for_tag() {
  local repo="$1"
  local tag="$2"
  local ref_json=""
  local obj_type=""
  local obj_sha=""

  ref_json="$(gh api "repos/${repo}/git/ref/tags/${tag}" 2>/dev/null || true)"
  if [[ -z "${ref_json}" ]]; then
    return 1
  fi

  obj_type="$(jq -r '.object.type' <<<"${ref_json}")"
  obj_sha="$(jq -r '.object.sha' <<<"${ref_json}")"

  if [[ "${obj_type}" == "tag" ]]; then
    ref_json="$(gh api "repos/${repo}/git/tags/${obj_sha}" 2>/dev/null || true)"
    if [[ -z "${ref_json}" ]]; then
      return 1
    fi
    obj_type="$(jq -r '.object.type' <<<"${ref_json}")"
    obj_sha="$(jq -r '.object.sha' <<<"${ref_json}")"
  fi

  if [[ "${obj_type}" != "commit" ]]; then
    return 1
  fi

  echo "${obj_sha}"
}

current_action_sha() {
  local repo="$1"
  local hit=""

  hit="$(rg --no-filename -o "uses:[[:space:]]*${repo}@[0-9a-f]{40}" "${WORKFLOW_FILES[@]}" 2>/dev/null | head -n1 || true)"
  if [[ -z "${hit}" ]]; then
    return 1
  fi
  sed -E 's/.*@([0-9a-f]{40})/\1/' <<<"${hit}"
}

set_action_sha_all_workflows() {
  local repo="$1"
  local new_sha="$2"
  local repo_escaped=""
  local file=""

  repo_escaped="$(sed 's/[\/&]/\\&/g' <<<"${repo}")"
  for file in "${WORKFLOW_FILES[@]}"; do
    sed -i -E "s|(uses:[[:space:]]*${repo_escaped}@)[0-9a-f]{40}|\\1${new_sha}|g" "${file}"
  done
}

current_codex_version_in_workflows() {
  local hit=""
  hit="$(rg --no-filename -o '@openai/codex@[0-9A-Za-z._-]+' "${WORKFLOW_FILES[@]}" 2>/dev/null | head -n1 || true)"
  if [[ -z "${hit}" ]]; then
    return 1
  fi
  sed -E 's#@openai/codex@##' <<<"${hit}"
}

latest_npm_version() {
  local pkg="$1"
  local version=""

  if command -v npm >/dev/null 2>&1; then
    version="$(npm view "${pkg}" version --silent 2>/dev/null || true)"
  fi
  if [[ -z "${version}" ]] && command -v curl >/dev/null 2>&1; then
    version="$(curl -fsSL "https://registry.npmjs.org/${pkg}/latest" | jq -r '.version' 2>/dev/null || true)"
  fi
  if [[ -z "${version}" || "${version}" == "null" ]]; then
    return 1
  fi

  echo "${version}"
}

set_codex_version_all_workflows() {
  local new_version="$1"
  local file=""

  for file in "${WORKFLOW_FILES[@]}"; do
    sed -i -E "s#(@openai/codex@)[0-9A-Za-z._-]+#\\1${new_version}#g" "${file}"
  done
}

DOCKER_VERSION_SOURCES=(
  "FZF_VERSION|junegunn/fzf"
  "EZA_VERSION|eza-community/eza"
  "STARSHIP_VERSION|starship/starship"
  "MICRO_VERSION|zyedidia/micro"
  "DUF_VERSION|muesli/duf"
  "GPING_VERSION|orf/gping"
  "FD_VERSION|sharkdp/fd"
  "LAZYGIT_VERSION|jesseduffield/lazygit"
  "GITUI_VERSION|gitui-org/gitui"
  "TOKEI_VERSION|XAMPPRocky/tokei"
  "YQ_VERSION|mikefarah/yq"
  "DELTA_VERSION|dandavison/delta"
  "DUST_VERSION|bootandy/dust"
  "PROCS_VERSION|dalance/procs"
  "BOTTOM_VERSION|ClementTsang/bottom"
  "XH_VERSION|ducaale/xh"
  "MCFLY_VERSION|cantino/mcfly"
  "GITLEAKS_VERSION|gitleaks/gitleaks"
  "HADOLINT_VERSION|hadolint/hadolint"
  "DIRENV_VERSION|direnv/direnv"
  "PRE_COMMIT_VERSION|pre-commit/pre-commit"
)

ACTION_PIN_SOURCES=(
  "actions/checkout|v4"
  "actions/setup-node|v4"
  "actions/github-script|v7"
  "actions/upload-artifact|v4"
  "anthropics/claude-code-action|v1"
)

if [[ "${MODE}" == "scan" ]]; then
  require_cmd rg
  echo "== Current Docker ARG Pins =="
  for item in "${DOCKER_VERSION_SOURCES[@]}"; do
    arg_name="${item%%|*}"
    repo="${item##*|}"
    current="$(docker_arg_value "${arg_name}")"
    printf '%-20s %-12s (%s)\n' "${arg_name}" "${current:-<missing>}" "${repo}"
  done

  echo
  echo "== Current Action SHA Pins =="
  for item in "${ACTION_PIN_SOURCES[@]}"; do
    repo="${item%%|*}"
    tag="${item##*|}"
    current_sha="$(current_action_sha "${repo}" || true)"
    printf '%-30s %-40s (%s)\n' "${repo}" "${current_sha:-<missing>}" "${tag}"
  done

  echo
  echo "== Current Codex Workflow Pin =="
  codex_current="$(current_codex_version_in_workflows || true)"
  printf '%-30s %s\n' "@openai/codex" "${codex_current:-<missing>}"
  exit 0
fi

require_cmd gh
require_cmd jq
require_cmd rg
require_cmd sed

LOOKUP_ERRORS=0
OUTDATED_COUNT=0

echo "== Docker ARG version check =="
for item in "${DOCKER_VERSION_SOURCES[@]}"; do
  arg_name="${item%%|*}"
  repo="${item##*|}"
  current="$(docker_arg_value "${arg_name}")"
  if [[ -z "${current}" ]]; then
    echo "[warn] Missing Docker ARG: ${arg_name}"
    LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
    continue
  fi

  latest="$(latest_release_version "${repo}" || true)"
  if [[ -z "${latest}" ]]; then
    echo "[warn] Failed to resolve latest release for ${repo}"
    LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
    continue
  fi

  if [[ "${current}" == "${latest}" ]]; then
    echo "[ok]   ${arg_name}: ${current}"
    continue
  fi

  OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
  echo "[diff] ${arg_name}: ${current} -> ${latest} (${repo})"

  if [[ "${MODE}" == "update" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "       dry-run: would update Dockerfile ARG ${arg_name}"
    else
      set_docker_arg_value "${arg_name}" "${latest}"
    fi
  fi
done

echo
echo "== GitHub Action SHA pin check =="
for item in "${ACTION_PIN_SOURCES[@]}"; do
  repo="${item%%|*}"
  tag="${item##*|}"

  current_sha="$(current_action_sha "${repo}" || true)"
  if [[ -z "${current_sha}" ]]; then
    echo "[warn] Missing action pin usage: ${repo}@<sha>"
    LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
    continue
  fi

  latest_sha="$(latest_action_sha_for_tag "${repo}" "${tag}" || true)"
  if [[ -z "${latest_sha}" ]]; then
    echo "[warn] Failed to resolve latest SHA for ${repo} ${tag}"
    LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
    continue
  fi

  if [[ "${current_sha}" == "${latest_sha}" ]]; then
    echo "[ok]   ${repo}: ${current_sha} (${tag})"
    continue
  fi

  OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
  echo "[diff] ${repo}: ${current_sha} -> ${latest_sha} (${tag})"

  if [[ "${MODE}" == "update" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "       dry-run: would update workflow uses: ${repo}@${latest_sha}"
    else
      set_action_sha_all_workflows "${repo}" "${latest_sha}"
    fi
  fi
done

echo
echo "== Codex npm pin check =="
codex_current="$(current_codex_version_in_workflows || true)"
if [[ -z "${codex_current}" ]]; then
  echo "[warn] Missing @openai/codex version pin in workflow files"
  LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
else
  codex_latest="$(latest_npm_version "@openai/codex" || true)"
  if [[ -z "${codex_latest}" ]]; then
    echo "[warn] Failed to resolve latest npm version for @openai/codex"
    LOOKUP_ERRORS=$((LOOKUP_ERRORS + 1))
  elif [[ "${codex_current}" == "${codex_latest}" ]]; then
    echo "[ok]   @openai/codex: ${codex_current}"
  else
    OUTDATED_COUNT=$((OUTDATED_COUNT + 1))
    echo "[diff] @openai/codex: ${codex_current} -> ${codex_latest}"
    if [[ "${MODE}" == "update" ]]; then
      if [[ "${DRY_RUN}" == "true" ]]; then
        echo "       dry-run: would update workflow codex npm pin"
      else
        set_codex_version_all_workflows "${codex_latest}"
      fi
    fi
  fi
fi

echo
if [[ "${LOOKUP_ERRORS}" -gt 0 ]]; then
  echo "Completed with lookup errors: ${LOOKUP_ERRORS}" >&2
  exit 1
fi

if [[ "${OUTDATED_COUNT}" -eq 0 ]]; then
  echo "All pinned versions are up to date."
  exit 0
fi

if [[ "${MODE}" == "check" ]]; then
  echo "Outdated pins found: ${OUTDATED_COUNT}" >&2
  exit 2
fi

if [[ "${MODE}" == "update" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "Dry-run complete. Planned updates: ${OUTDATED_COUNT}"
  else
    echo "Update complete. Updated pins: ${OUTDATED_COUNT}"
    echo "Changed files:"
    git -C "${REPO_ROOT}" diff --name-only
  fi
fi
