#!/bin/bash
set -euo pipefail

# Docker storage guard for host disk pressure.
#
# Why this exists:
# - Repeated image builds can accumulate reclaimable Docker data (images/build cache).
# - When reclaimable data grows too much, builds may fail with "no space left on device".
#
# What this script does:
# 1) Reads `docker system df` reclaimable size.
# 2) Compares against a threshold.
# 3) In `prune` mode, runs safe cleanup commands when threshold is met.
#
# Defaults are intentionally conservative:
# - check mode (no deletion)
# - threshold 8 GiB reclaimable
# - prune mode only removes build cache + dangling/unused images.

MODE="check"
THRESHOLD_GB="${DOCKER_STORAGE_PRUNE_THRESHOLD_GB:-8}"
FORCE=false

usage() {
  cat <<'EOF'
Usage:
  scripts/docker-storage-guard.sh [check|prune] [options]

Modes:
  check                Print reclaimable Docker size and threshold decision (default)
  prune                Run cleanup when threshold is met

Options:
  --threshold-gb N     Reclaimable threshold in GiB (default: 8 or env DOCKER_STORAGE_PRUNE_THRESHOLD_GB)
  --force              In prune mode, clean even if threshold is not met
  -h, --help           Show this help

Examples:
  scripts/docker-storage-guard.sh check
  scripts/docker-storage-guard.sh prune --threshold-gb 12
  scripts/docker-storage-guard.sh prune --force
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 1
  fi
}

validate_numeric() {
  local value="$1"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "Invalid numeric value: $value" >&2
    exit 1
  fi
}

size_to_bytes() {
  local value="$1"
  local number=""
  local unit=""

  if [[ "$value" == "0" || "$value" == "0B" ]]; then
    echo "0"
    return 0
  fi

  number="$(sed -E 's/^([0-9]+([.][0-9]+)?).*/\1/' <<<"$value")"
  unit="$(sed -E 's/^[0-9]+([.][0-9]+)?([A-Za-z]+).*/\2/' <<<"$value")"

  awk -v n="$number" -v u="$unit" '
    BEGIN {
      scale = 1;
      if (u == "B") scale = 1;
      else if (u == "KB" || u == "KiB") scale = 1024;
      else if (u == "MB" || u == "MiB") scale = 1024 * 1024;
      else if (u == "GB" || u == "GiB") scale = 1024 * 1024 * 1024;
      else if (u == "TB" || u == "TiB") scale = 1024 * 1024 * 1024 * 1024;
      else if (u == "PB" || u == "PiB") scale = 1024 * 1024 * 1024 * 1024 * 1024;
      printf "%.0f\n", n * scale;
    }
  '
}

bytes_to_human() {
  local bytes="$1"
  awk -v b="$bytes" '
    BEGIN {
      split("B KiB MiB GiB TiB PiB", u, " ");
      i = 1;
      while (b >= 1024 && i < 6) {
        b /= 1024;
        i++;
      }
      if (i == 1) printf "%d %s", b, u[i];
      else printf "%.2f %s", b, u[i];
    }
  '
}

collect_reclaimable_bytes() {
  local type=""
  local reclaim_field=""
  local reclaim_value=""
  local reclaim_bytes=0

  RECLAIMABLE_TOTAL_BYTES=0
  RECLAIMABLE_IMAGES_BYTES=0
  RECLAIMABLE_BUILD_CACHE_BYTES=0

  while IFS='|' read -r type _ reclaim_field; do
    reclaim_value="$(awk '{print $1}' <<<"$reclaim_field")"
    reclaim_bytes="$(size_to_bytes "$reclaim_value")"
    RECLAIMABLE_TOTAL_BYTES=$((RECLAIMABLE_TOTAL_BYTES + reclaim_bytes))

    case "$type" in
      Images)
        RECLAIMABLE_IMAGES_BYTES="$reclaim_bytes"
        ;;
      "Build Cache")
        RECLAIMABLE_BUILD_CACHE_BYTES="$reclaim_bytes"
        ;;
    esac
  done < <(docker system df --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}')
}

print_summary() {
  echo "[docker-storage-guard] Summary"
  echo "  Threshold: $(printf '%.2f' "$THRESHOLD_GB") GiB"
  echo "  Reclaimable total: $(bytes_to_human "$RECLAIMABLE_TOTAL_BYTES")"
  echo "  Reclaimable images: $(bytes_to_human "$RECLAIMABLE_IMAGES_BYTES")"
  echo "  Reclaimable build cache: $(bytes_to_human "$RECLAIMABLE_BUILD_CACHE_BYTES")"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check|prune)
      MODE="$1"
      shift
      ;;
    --threshold-gb)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --threshold-gb" >&2
        exit 1
      fi
      THRESHOLD_GB="$1"
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd docker
require_cmd awk
require_cmd sed
validate_numeric "$THRESHOLD_GB"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable. Check socket mount/permissions first." >&2
  exit 1
fi

collect_reclaimable_bytes
print_summary

THRESHOLD_BYTES="$(awk -v n="$THRESHOLD_GB" 'BEGIN { printf "%.0f\n", n * 1024 * 1024 * 1024 }')"
SHOULD_PRUNE=false
if (( RECLAIMABLE_TOTAL_BYTES >= THRESHOLD_BYTES )); then
  SHOULD_PRUNE=true
fi

if [[ "$MODE" == "check" ]]; then
  if [[ "$SHOULD_PRUNE" == "true" ]]; then
    echo "[docker-storage-guard] Threshold met. Run: scripts/docker-storage-guard.sh prune --threshold-gb $THRESHOLD_GB"
  else
    echo "[docker-storage-guard] Threshold not met. No cleanup needed."
  fi
  exit 0
fi

if [[ "$SHOULD_PRUNE" != "true" && "$FORCE" != "true" ]]; then
  echo "[docker-storage-guard] Skip prune (threshold not met). Use --force to override."
  exit 0
fi

echo "[docker-storage-guard] Running cleanup: docker builder prune -af"
docker builder prune -af
echo "[docker-storage-guard] Running cleanup: docker image prune -af"
docker image prune -af

echo "[docker-storage-guard] Post-cleanup status:"
collect_reclaimable_bytes
print_summary
