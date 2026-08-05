#!/usr/bin/env bash
# Smoke test: assert every tool advertised in README.md is present and runnable
# in the built image. Usage: ./test/smoke.sh [image-tag]
#
# Entries may list alternatives separated by "|" — any one satisfies the check.
# This exists because a few package/binary names differ across upstream
# versions (7-zip ships 7zz/7za/7z; ImageMagick 6 ships convert, 7 ships magick).
set -eu

IMAGE="${1:-ghcr.io/d7eeem/toolbox-cli:latest}"

TOOLS="ncdu dua eza fdfind file 7zz|7z|7za zstd pigz unzip unrar
ffmpeg ffprobe ffmpegthumbnailer mediainfo exiftool convert|magick
nvim rg batcat jq fzf less glow
htop tmux curl wget git ssh
yazi ya"

echo "Smoke testing image: $IMAGE"

docker run --rm -i "$IMAGE" bash -s -- $TOOLS <<'SCRIPT'
set -u
failed=0
for entry in "$@"; do
  found=""
  # Split on "|" and accept the first alternative that resolves.
  IFS='|'
  for name in $entry; do
    if command -v "$name" >/dev/null 2>&1; then
      found="$name"
      break
    fi
  done
  unset IFS

  if [ -z "$found" ]; then
    echo "FAIL $entry (none of these are on PATH)"
    failed=$((failed + 1))
    continue
  fi

  # Best-effort execution probe. Many of these do not support --version
  # (less uses -V; unrar and 7-zip print a banner and may exit non-zero),
  # so a non-zero exit here is not treated as a failure. The binding
  # constraint is presence on PATH.
  "$found" --version >/dev/null 2>&1 || "$found" -V >/dev/null 2>&1 || true
  echo "ok   $found"
done

if [ "$failed" -gt 0 ]; then
  echo "---"
  echo "$failed tool(s) missing"
  exit 1
fi
echo "---"
echo "all tools present"
SCRIPT
