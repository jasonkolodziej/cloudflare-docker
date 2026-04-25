#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="ghcr.io/jasonkolodziej/cloudflare-warp-docker-warp"
TARGET_IMAGE="ghcr.io/jasonkolodziej/cloudflare-warp-docker"
SHOW_MISSING=0
STRICT=0
IGNORE_MISSING_SOURCE=0

usage() {
  cat <<'EOF'
Show retag migration progress between two GHCR container packages.

Usage:
  ./scripts/check-ghcr-retag-status.sh [options]

Options:
  --source-image IMAGE   Source GHCR image (default: ghcr.io/jasonkolodziej/cloudflare-warp-docker-warp)
  --target-image IMAGE   Target GHCR image (default: ghcr.io/jasonkolodziej/cloudflare-warp-docker)
  --show-missing         Print tags present in source but missing in target
  --strict               Exit with code 1 when source tags are missing in target
  --ignore-missing-source
                         Treat missing source package as "nothing to migrate"
  -h, --help             Show this help

Requirements:
- gh CLI authenticated with permission to read package metadata.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

parse_ghcr_image() {
  local image="$1"
  local rest owner package

  image="${image#docker://}"
  image="${image%%@*}"
  image="${image%%:*}"

  if [[ "$image" != ghcr.io/*/* ]]; then
    echo "Unsupported GHCR image format: $1" >&2
    exit 1
  fi

  rest="${image#ghcr.io/}"
  owner="${rest%%/*}"
  package="${rest#*/}"

  printf '%s\n%s\n' "$owner" "$package"
}

fetch_tags_from_gh() {
  local image="$1"
  local allow_missing="${2:-0}"
  local owner package scope endpoint
  local parsed

  parsed="$(parse_ghcr_image "$image")"
  owner="$(printf '%s' "$parsed" | sed -n '1p')"
  package="$(printf '%s' "$parsed" | sed -n '2p')"

  for scope in users orgs; do
    endpoint="/${scope}/${owner}/packages/container/${package}"
    if gh api -H "Accept: application/vnd.github+json" "$endpoint" >/dev/null 2>&1; then
      gh api -H "Accept: application/vnd.github+json" \
        "${endpoint}/versions?per_page=100" \
        --paginate \
        --jq '.[].metadata.container.tags[]' \
        | sed '/^null$/d' \
        | sort -u
      return 0
    fi
  done

  if [[ "$allow_missing" -eq 1 ]]; then
    return 2
  fi

  echo "Unable to resolve package metadata via gh api for image: $image" >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-image)
      SOURCE_IMAGE="$2"
      shift 2
      ;;
    --target-image)
      TARGET_IMAGE="$2"
      shift 2
      ;;
    --show-missing)
      SHOW_MISSING=1
      shift
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --ignore-missing-source)
      IGNORE_MISSING_SOURCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd gh

source_tags_file="$(mktemp)"
target_tags_file="$(mktemp)"
cleanup() {
  rm -f "$source_tags_file" "$target_tags_file"
}
trap cleanup EXIT

if ! fetch_tags_from_gh "$SOURCE_IMAGE" "$IGNORE_MISSING_SOURCE" > "$source_tags_file"; then
  rc=$?
  if [[ "$rc" -eq 2 ]]; then
    echo "Source image: $SOURCE_IMAGE"
    echo "Target image: $TARGET_IMAGE"
    echo "Source package not found. Nothing to migrate."
    echo "Migration progress: 100.00%"
    exit 0
  fi
  exit "$rc"
fi
fetch_tags_from_gh "$TARGET_IMAGE" > "$target_tags_file"

source_count="$(wc -l < "$source_tags_file" | tr -d ' ')"
target_count="$(wc -l < "$target_tags_file" | tr -d ' ')"

missing_count="$(comm -23 "$source_tags_file" "$target_tags_file" | wc -l | tr -d ' ')"
extra_count="$(comm -13 "$source_tags_file" "$target_tags_file" | wc -l | tr -d ' ')"

if [[ "$source_count" -eq 0 ]]; then
  progress="0.00"
else
  migrated=$((source_count - missing_count))
  progress="$(awk -v migrated="$migrated" -v total="$source_count" 'BEGIN { printf "%.2f", (migrated * 100.0) / total }')"
fi

echo "Source image: $SOURCE_IMAGE"
echo "Target image: $TARGET_IMAGE"
echo "Source tags: $source_count"
echo "Target tags: $target_count"
echo "Missing from target: $missing_count"
echo "Only in target: $extra_count"
echo "Migration progress: ${progress}%"

if [[ "$SHOW_MISSING" -eq 1 ]]; then
  echo
  echo "Missing tags:"
  comm -23 "$source_tags_file" "$target_tags_file"
fi

if [[ "$STRICT" -eq 1 ]] && [[ "$missing_count" -gt 0 ]]; then
  exit 1
fi
