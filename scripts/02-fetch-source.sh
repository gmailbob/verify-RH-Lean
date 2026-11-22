#!/usr/bin/env bash
# Step 2: download the claimed formalization, verify every hash, extract it safely,
# and record a baseline hash of every source file.
source "$(dirname "$0")/lib.sh"
log_to 02-fetch-source.log

mkdir -p "$DL"

log "download announcement and $ARCHIVE_PARTS archive parts from $SOURCE_BASE_URL"
fetch() {  # fetch <name>
  if [[ -s "$DL/$1" ]]; then echo "  $1 already present"; return; fi
  curl -fsSL --retry 5 --retry-delay 5 -o "$DL/$1.partial" "$SOURCE_BASE_URL/$1"
  mv "$DL/$1.partial" "$DL/$1"
  echo "  $1 $(stat -c %s "$DL/$1") bytes"
}
fetch "$ANNOUNCEMENT_FILE"
parts=()
for i in $(seq -w 1 "$ARCHIVE_PARTS"); do
  p="$ARCHIVE_NAME.part$i"; parts+=("$p"); fetch "$p"
done

log "verify hashes"
(( $(stat -c %s "$DL/$ANNOUNCEMENT_FILE") == ANNOUNCEMENT_SIZE )) && sha256_is "$DL/$ANNOUNCEMENT_FILE" "$ANNOUNCEMENT_SHA256" \
  && ok "$ANNOUNCEMENT_FILE size and sha256" || bad "$ANNOUNCEMENT_FILE size or sha256"
(cd "$DL" && sha256sum "${parts[@]}") > "$OUT/archive-parts.sha256"
if diff <(sort -k2 "$REPO/expected/archive-parts.sha256") <(sort -k2 "$OUT/archive-parts.sha256"); then
  ok "all $ARCHIVE_PARTS parts match expected/archive-parts.sha256"
else
  bad "part hashes differ (diff above)"
fi
(( FAILS == 0 )) || finish

log "concatenate"
(cd "$DL" && cat "${parts[@]}") > "$DL/$ARCHIVE_NAME"
(( $(stat -c %s "$DL/$ARCHIVE_NAME") == ARCHIVE_SIZE )) && ok "archive size $ARCHIVE_SIZE" || bad "archive size"
sha256_is "$DL/$ARCHIVE_NAME" "$ARCHIVE_SHA256" && ok "archive sha256 $ARCHIVE_SHA256" || bad "archive sha256"
(( FAILS == 0 )) || finish

log "inspect archive members before extracting"
if python3 -I "$REPO/scripts/tools/check_tar.py" "$DL/$ARCHIVE_NAME" "$EXPECTED_ROOT_DIR" "$EXPECTED_FILES" | sed 's/^/  /'; then
  ok "only regular files and directories under $EXPECTED_ROOT_DIR/, no unsafe paths, $EXPECTED_FILES files"
else
  bad "archive failed member checks"; finish
fi

log "extract into $SRC"
if [[ -d "$PROJ" ]]; then
  [[ "${FORCE:-0}" == 1 ]] || die "$PROJ already exists. Remove it, or set FORCE=1 to re-extract over it."
  rm -rf "$PROJ"
fi
mkdir -p "$SRC"
tar -xzf "$DL/$ARCHIVE_NAME" -C "$SRC" --no-same-owner --no-same-permissions
nfiles=$(find "$PROJ" -type f | wc -l)
nlean=$(find "$PROJ" -type f -name '*.lean' | wc -l)
(( nfiles == EXPECTED_FILES )) && ok "$nfiles files extracted" || bad "$nfiles files extracted, expected $EXPECTED_FILES"
(( nlean == EXPECTED_LEAN_FILES )) && ok "$nlean .lean files" || bad "$nlean .lean files, expected $EXPECTED_LEAN_FILES"

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

log "baseline hash of every source file"
"$REPO/scripts/tools/hash-tree.sh" "$PROJ" "$OUT/sources.prebuild.sha256.zst" | sed 's/^/  /'
ok "wrote $OUT/sources.prebuild.sha256.zst"

finish
