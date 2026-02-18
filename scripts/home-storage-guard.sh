#!/usr/bin/env bash
set -euo pipefail

# Home storage guard for persisted sandbox home volume.
#
# Why this exists:
# - Agent toolchains accumulate caches under ~/.cache, ~/.npm, and tmp folders.
# - Playwright self-heal may leave a duplicate Chromium payload in
#   ~/.cache/ms-playwright even when /ms-playwright already has the same payload.
#
# Modes:
# - check: print current usage without deleting anything
# - prune: dedupe known duplicates + remove safe caches

MODE="${1:-check}"
if [[ "$#" -gt 0 ]]; then
  shift
fi

AGGRESSIVE=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --aggressive)
      AGGRESSIVE=1
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
  shift
done

HOME_DIR="${HOME:-/home/sandbox}"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME_DIR/.cache}"
PLAYWRIGHT_PRIMARY_ROOT="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"
PLAYWRIGHT_FALLBACK_ROOT="$CACHE_ROOT/ms-playwright"

usage() {
  cat <<'USAGE'
Usage:
  scripts/home-storage-guard.sh [check|prune] [--aggressive]

Modes:
  check   Show sandbox home usage summary (default)
  prune   Remove safe caches and dedupe Playwright fallback cache

Options:
  --aggressive   Also remove re-creatable tool caches (Neovim mason packages,
                 Claude local versions/telemetry/debug logs)
USAGE
}

bytes_to_human() {
  local bytes="$1"
  awk -v n="$bytes" '
    BEGIN {
      split("B KiB MiB GiB TiB", u, " ")
      i = 1
      while (n >= 1024 && i < 5) {
        n /= 1024
        i++
      }
      printf("%.2f %s", n, u[i])
    }
  '
}

dir_bytes() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  du -sb "$path" 2>/dev/null | awk '{print $1}'
}

find_playwright_chromium_binary() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    return 1
  fi
  find "$root" -type f \( -path '*/chrome-linux/chrome' -o -path '*/chrome-linux64/chrome' \) -print -quit
}

chromium_revision() {
  local chromium_bin="$1"
  basename "$(dirname "$(dirname "$chromium_bin")")"
}

print_summary() {
  local home_bytes cache_bytes npm_bytes local_bytes
  home_bytes="$(dir_bytes "$HOME_DIR")"
  cache_bytes="$(dir_bytes "$CACHE_ROOT")"
  npm_bytes="$(dir_bytes "$HOME_DIR/.npm")"
  local_bytes="$(dir_bytes "$HOME_DIR/.local")"

  echo "[home-storage-guard] Summary for $HOME_DIR"
  echo "  HOME total : $(bytes_to_human "$home_bytes")"
  echo "  .cache     : $(bytes_to_human "$cache_bytes")"
  echo "  .npm       : $(bytes_to_human "$npm_bytes")"
  echo "  .local     : $(bytes_to_human "$local_bytes")"
  echo
  echo "[home-storage-guard] Top-level directories"
  du -xhd1 "$HOME_DIR" 2>/dev/null | sort -h
}

dedupe_playwright_cache() {
  local primary_bin=""
  local fallback_bin=""
  local primary_revision=""
  local fallback_revision=""

  if [[ ! -d "$PLAYWRIGHT_PRIMARY_ROOT" ]]; then
    return 0
  fi

  if [[ -L "$PLAYWRIGHT_FALLBACK_ROOT" ]]; then
    if [[ "$(readlink "$PLAYWRIGHT_FALLBACK_ROOT" 2>/dev/null || true)" == "$PLAYWRIGHT_PRIMARY_ROOT" ]]; then
      return 0
    fi
  fi

  if ! primary_bin="$(find_playwright_chromium_binary "$PLAYWRIGHT_PRIMARY_ROOT" 2>/dev/null)"; then
    return 0
  fi

  fallback_bin="$(find_playwright_chromium_binary "$PLAYWRIGHT_FALLBACK_ROOT" 2>/dev/null || true)"
  if [[ -n "$fallback_bin" ]]; then
    primary_revision="$(chromium_revision "$primary_bin")"
    fallback_revision="$(chromium_revision "$fallback_bin")"
    if [[ "$primary_revision" != "$fallback_revision" ]]; then
      return 0
    fi
  fi

  mkdir -p "$(dirname "$PLAYWRIGHT_FALLBACK_ROOT")"
  rm -rf "$PLAYWRIGHT_FALLBACK_ROOT"
  ln -s "$PLAYWRIGHT_PRIMARY_ROOT" "$PLAYWRIGHT_FALLBACK_ROOT"
  echo "[home-storage-guard] Deduped Playwright cache: $PLAYWRIGHT_FALLBACK_ROOT -> $PLAYWRIGHT_PRIMARY_ROOT"
}

prune_safe_caches() {
  # npm cache is redownloadable and safe to clear.
  npm cache clean --force >/dev/null 2>&1 || true

  rm -rf \
    "$HOME_DIR/.npm/_npx" \
    "$HOME_DIR/.npm/_cacache/tmp" \
    "$CACHE_ROOT/node-gyp" \
    "$CACHE_ROOT/agent-sandbox/tmp" \
    "$CACHE_ROOT/pw-tmp" \
    /tmp/node-compile-cache \
    2>/dev/null || true

  # Remove transient Playwright probe/bootstrap leftovers.
  find "$CACHE_ROOT" -maxdepth 1 -type d -name 'pw-probe-*' -exec rm -rf {} + 2>/dev/null || true
  find /tmp -maxdepth 1 -type d -name 'playwright-probe-*' -exec rm -rf {} + 2>/dev/null || true
  find /tmp -maxdepth 1 -type d -name 'playwright-bootstrap.*' -exec rm -rf {} + 2>/dev/null || true
  find /tmp -maxdepth 1 -type f -name 'playwright-install.*.log' -delete 2>/dev/null || true
  find /tmp -maxdepth 1 -type d -name 'bunx-*' -exec rm -rf {} + 2>/dev/null || true

  # tealdeer pages are redownloadable.
  rm -rf "$CACHE_ROOT/tealdeer" 2>/dev/null || true
}

prune_aggressive_caches() {
  rm -rf \
    "$HOME_DIR/.local/share/claude/versions" \
    "$HOME_DIR/.claude/telemetry" \
    "$HOME_DIR/.claude/debug" \
    "$HOME_DIR/.local/share/nvim/mason/packages" \
    "$HOME_DIR/.local/share/nvim/mason/registries" \
    2>/dev/null || true
}

case "$MODE" in
  check)
    print_summary
    ;;
  prune)
    echo "[home-storage-guard] Before prune:"
    print_summary
    dedupe_playwright_cache
    prune_safe_caches
    if [[ "$AGGRESSIVE" -eq 1 ]]; then
      prune_aggressive_caches
    fi
    echo
    echo "[home-storage-guard] After prune:"
    print_summary
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac
