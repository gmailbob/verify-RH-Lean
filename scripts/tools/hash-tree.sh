#!/usr/bin/env bash
# Hash every file under a project directory, excluding Lake build outputs (.lake/).
# Usage: hash-tree.sh <project-dir> <out.sha256.zst>
# Output: zstd-compressed `sha256sum` lines, sorted by path.
set -euo pipefail
PROJ="${1:?usage: hash-tree.sh <project-dir> <out.sha256.zst>}"
OUT="$(realpath -m "${2:?usage: hash-tree.sh <project-dir> <out.sha256.zst>}")"
cd "$PROJ"
find . -path ./.lake -prune -o -type f -print0 \
  | xargs -0 -P "$(nproc)" -n 2000 sha256sum \
  | LC_ALL=C sort -k2 \
  | zstd -q -19 -f -o "$OUT"
echo "files hashed: $(zstdcat "$OUT" | wc -l)"
echo "digest of the hash list: $(zstdcat "$OUT" | sha256sum | cut -d' ' -f1)"
