#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="ghcr.io/jasonkolodziej/cloudflare-warp-docker-warp"
TARGET_IMAGE="ghcr.io/jasonkolodziej/cloudflare-warp-docker"
DRY_RUN=0
FORCE=0
ONLY_TAGS=""

usage() {
  cat <<'EOF'
Bulk-copy GHCR tags from one image name to another without rebuilding.

Usage:
  ./scripts/retag-ghcr-package.sh [options]

Options:
  --source-image IMAGE   Source GHCR image (default: ghcr.io/jasonkolodziej/cloudflare-warp-docker-warp)
  --target-image IMAGE   Target GHCR image (default: ghcr.io/jasonkolodziej/cloudflare-warp-docker)
  --only-tags CSV        Copy only these tags (comma-separated)
  --dry-run              Print operations without copying
  --force                Copy even when destination tag already exists
  -h, --help             Show this help

Notes:
- Requires: gh, skopeo
- Authenticate first, for example:
    echo "$GHCR_PAT" | podman login ghcr.io -u <github-user> --password-stdin
- Uses skopeo copy --all to preserve multi-arch manifests.
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
    --only-tags)
      ONLY_TAGS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
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
require_cmd skopeo

tags=()

if [[ -n "$ONLY_TAGS" ]]; then
  IFS=',' read -r -a tags <<< "$ONLY_TAGS"
else
  while IFS= read -r tag; do
    if [[ -n "$tag" ]]; then
      tags+=("$tag")
    fi
  done < <(fetch_tags_from_gh "$SOURCE_IMAGE")
fi

if [[ ${#tags[@]} -eq 0 ]]; then
  echo "No tags found to copy." >&2
  exit 1
fi

echo "Source image: $SOURCE_IMAGE"
echo "Target image: $TARGET_IMAGE"
echo "Tag count: ${#tags[@]}"

copied=0
skipped=0
failed=0

declare -a failed_tags

for tag in "${tags[@]}"; do
  src_ref="docker://${SOURCE_IMAGE}:${tag}"
  dst_ref="docker://${TARGET_IMAGE}:${tag}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] skopeo copy --all ${src_ref} ${dst_ref}"
    continue
  fi

  if [[ "$FORCE" -ne 1 ]] && skopeo inspect "$dst_ref" >/dev/null 2>&1; then
    echo "[skip] ${tag} (already exists at destination)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "[copy] ${tag}"
  if skopeo copy --all "$src_ref" "$dst_ref"; then
    copied=$((copied + 1))
  else
    failed=$((failed + 1))
    failed_tags+=("$tag")
    echo "[fail] ${tag}" >&2
  fi
done

echo "Summary: copied=${copied} skipped=${skipped} failed=${failed}"

if [[ "$failed" -gt 0 ]]; then
  printf 'Failed tags:\n' >&2
  printf ' - %s\n' "${failed_tags[@]}" >&2
  exit 1
fi
