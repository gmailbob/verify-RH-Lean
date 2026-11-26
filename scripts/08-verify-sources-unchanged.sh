#!/usr/bin/env bash
# Step 8: confirm that what was built and audited is exactly what was published.
# Hashes every file in the project tree (excluding the build directory .lake/) and compares
# it with (a) the pinned content digest SOURCE_TREE_SHA256 and (b) the baseline from step 2.
# Also checks that the clone is still at the pinned commit with no modified tracked files.
# Run it after the build; it can also be run before, as a sanity check.
source "$(dirname "$0")/lib.sh"
need_project
log_to 08-verify-sources-unchanged.log

log "hash the project tree now"
"$REPO/scripts/tools/hash-tree.sh" "$PROJ" "$OUT/sources.postbuild.sha256.zst" | sed 's/^/  /'
digest=$(zstdcat "$OUT/sources.postbuild.sha256.zst" | sha256sum | cut -d' ' -f1)
[[ "$digest" == "$SOURCE_TREE_SHA256" ]] \
  && ok "project tree matches the pinned content digest (no files added, removed or changed)" \
  || bad "content digest $digest differs from the pinned $SOURCE_TREE_SHA256"

if [[ -f "$OUT/sources.prebuild.sha256.zst" ]]; then
  if diff <(zstdcat "$OUT/sources.prebuild.sha256.zst") <(zstdcat "$OUT/sources.postbuild.sha256.zst") > "$OUT/sources-vs-baseline.diff"; then
    ok "identical to the baseline from step 2"
  else
    bad "differs from the baseline: $(grep -c '^[<>]' "$OUT/sources-vs-baseline.diff") lines, see $OUT/sources-vs-baseline.diff"
  fi
else
  warn "no baseline from step 2 found"
fi

log "git state of the clone"
[[ "$(git -C "$CLONE" rev-parse HEAD)" == "$SOURCE_COMMIT" ]] && ok "HEAD is the pinned commit $SOURCE_COMMIT" || bad "HEAD is not the pinned commit"
[[ -z "$(git -C "$CLONE" status --porcelain --untracked-files=no)" ]] && ok "no modified tracked files" || bad "tracked files were modified"
finish
