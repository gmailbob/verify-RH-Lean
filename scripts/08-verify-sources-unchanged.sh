#!/usr/bin/env bash
# Step 8: confirm that what was built and audited is exactly what was published.
# Hashes every file in the project tree after the build (excluding .lake/) and
# compares it with (a) the hashes of the files inside the verified archive and
# (b) the baseline taken in step 2.
source "$(dirname "$0")/lib.sh"
need_project
log_to 08-verify-sources-unchanged.log

log "re-verify the archive"
sha256_is "$DL/$ARCHIVE_NAME" "$ARCHIVE_SHA256" && ok "archive sha256 unchanged" || bad "archive sha256 changed"

log "hash the project tree now"
"$REPO/scripts/tools/hash-tree.sh" "$PROJ" "$OUT/sources.postbuild.sha256.zst" | sed 's/^/  /'

log "hash the files inside the archive"
python3 -I "$REPO/scripts/tools/tar_hashes.py" "$DL/$ARCHIVE_NAME" "$EXPECTED_ROOT_DIR" > "$OUT/archive-members.sha256"
echo "  $(wc -l < "$OUT/archive-members.sha256") members hashed"

norm() { LC_ALL=C sort -k2 "$@"; }
if diff <(norm "$OUT/archive-members.sha256") <(zstdcat "$OUT/sources.postbuild.sha256.zst" | norm) > "$OUT/sources-vs-archive.diff"; then
  ok "project tree is byte-identical to the archive contents (no files added, removed or changed)"
else
  bad "project tree differs from the archive: $(grep -c '^[<>]' "$OUT/sources-vs-archive.diff") lines, see $OUT/sources-vs-archive.diff"
fi
if [[ -f "$OUT/sources.prebuild.sha256.zst" ]]; then
  if diff <(zstdcat "$OUT/sources.prebuild.sha256.zst" | norm) <(zstdcat "$OUT/sources.postbuild.sha256.zst" | norm) >/dev/null; then
    ok "matches the pre-build baseline from step 2"
  else
    bad "differs from the pre-build baseline"
  fi
else
  warn "no pre-build baseline found"
fi
finish
