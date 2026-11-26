#!/usr/bin/env bash
# Step 2: download the published proof from scratch, check that it is exactly the pinned
# content, and record a baseline hash of every file.
#
# The source is a fresh clone of $SOURCE_REPO_URL at $SOURCE_COMMIT; nothing already on this
# machine is used. Two independent pins: the git commit id, and SOURCE_TREE_SHA256, a sha256
# over the sha256 of every file under $SOURCE_SUBDIR/ (so the content does not rest on git's
# SHA-1 alone).
source "$(dirname "$0")/lib.sh"
log_to 02-fetch-source.log

log "clone $SOURCE_REPO_URL"
if [[ -e "$CLONE" ]]; then
  [[ "${FORCE:-0}" == 1 ]] || die "$CLONE already exists. Remove it, or set FORCE=1 to clone again (this also deletes any build inside it)."
  rm -rf "${CLONE:?}"
fi
mkdir -p "$SRC"
pinned_checkout "$SOURCE_REPO_URL" "$CLONE" "$SOURCE_COMMIT"
(( FAILS == 0 )) || finish
[[ -f "$PROJ/lakefile.toml" ]] || { bad "no $SOURCE_SUBDIR/lakefile.toml in the clone"; finish; }

log "shape of $SOURCE_SUBDIR/"
# Only regular files: no symlinks (which could point outside the tree) and no submodules.
modes=$(git -C "$CLONE" ls-tree -r "$SOURCE_COMMIT" -- "$SOURCE_SUBDIR" | awk '{print $1}' | sort -u | tr '\n' ' ')
[[ "$modes" =~ ^(100644\ |100755\ )+$ ]] && ok "git tree holds only regular files (modes: $modes)" || bad "unexpected git file modes: $modes"
[[ -z "$(find "$PROJ" -type l -print -quit)" ]] && ok "no symlinks" || bad "symlinks present"
nfiles=$(find "$PROJ" -type f | wc -l)
nlean=$(find "$PROJ" -type f -name '*.lean' | wc -l)
nsrc=$(find "$PROJ/src" -type f -name '*.lean' | wc -l)
nother=$(find "$PROJ/src" -type f ! -name '*.lean' | wc -l)
(( nfiles == EXPECTED_FILES )) && ok "$nfiles files" || bad "$nfiles files, expected $EXPECTED_FILES"
(( nlean == EXPECTED_LEAN_FILES )) && ok "$nlean .lean files" || bad "$nlean .lean files, expected $EXPECTED_LEAN_FILES"
(( nsrc == EXPECTED_SRC_LEAN_FILES && nother == 0 )) && ok "$nsrc .lean files under src/, and nothing else there" \
  || bad "$nsrc .lean and $nother other files under src/, expected $EXPECTED_SRC_LEAN_FILES and 0"
# A lakefile.lean would be Lean code that Lake runs; lakefile.toml is declarative.
[[ ! -e "$PROJ/lakefile.lean" ]] && ok "build configuration is declarative (lakefile.toml only)" || bad "lakefile.lean present"

log "content hash of every file (baseline)"
"$REPO/scripts/tools/hash-tree.sh" "$PROJ" "$OUT/sources.prebuild.sha256.zst" | sed 's/^/  /'
digest=$(zstdcat "$OUT/sources.prebuild.sha256.zst" | sha256sum | cut -d' ' -f1)
[[ "$digest" == "$SOURCE_TREE_SHA256" ]] && ok "content matches the pinned SOURCE_TREE_SHA256" \
  || bad "content digest $digest differs from the pinned $SOURCE_TREE_SHA256"

log "project pins"
tcfile=$(tr -d '[:space:]' < "$PROJ/lean-toolchain")
[[ "$tcfile" == "leanprover/lean4:v$LEAN_VERSION" ]] && ok "lean-toolchain is $tcfile" || bad "lean-toolchain is '$tcfile', expected leanprover/lean4:v$LEAN_VERSION"
grep -q "rev = \"$MATHLIB_REV\"" "$PROJ/lakefile.toml" && ok "lakefile.toml pins mathlib $MATHLIB_REV" || bad "lakefile.toml mathlib rev"
python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))
for p in m["packages"]:
    print(p["name"], p["rev"], p.get("url", "-"))
' "$PROJ/lake-manifest.json" | sort > "$OUT/lake-manifest.revs"
if diff <(sort "$REPO/expected/lake-manifest.revs") "$OUT/lake-manifest.revs"; then
  ok "lake-manifest.json revisions match expected/lake-manifest.revs"
else
  bad "lake-manifest.json revisions differ (diff above)"
fi

finish
