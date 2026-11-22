#!/usr/bin/env bash
# Step 9 (optional, recommended): check the proof with an independently written kernel.
#
# Steps 5 and 7 both trust Lean's own kernel. This step exports the proof with lean4export
# and checks the export with con-leche, a separate kernel implementation. A bug in Lean's
# kernel would not carry over to it. Same tools, revisions and export targets as MIT's run
# (https://math.mit.edu/~drew/grh/), so the export's hash can also be compared with theirs.
#
# Stages (UPTO=setup | export | check, default check = all three):
#   setup   install Lean v$CHECKER_LEAN_VERSION (hash-checked, as in step 1); build lean4export
#           (pinned, with Lean v$LEAN_VERSION) and con-leche (pinned, with v$CHECKER_LEAN_VERSION).
#           Small builds; SETUP_JOBS (default 4) limits their parallelism.
#   export  lean4export Main -- <expected/export-targets.txt>  ->  $OUT/solution.ndjson (~62 GB)
#           Its sha256 is compared with MIT's export. Equal means MIT's nanoda and con-leche
#           results apply to exactly this build; a difference is reported, not a failure.
#   check   con-leche checks the export with all cores (~50 GB RAM).
# EXPORT_SOURCE=mit: instead of exporting our build, download MIT's published export and
#   verify it against their two published hashes (compressed and unpacked); then check it.
# Export and check load the whole proof; they refuse to start while leanchecker (step 7) runs,
# unless FORCE=1. An existing solution.ndjson is reused unless REEXPORT=1.
source "$(dirname "$0")/lib.sh"
need_toolchain
log_to 09-independent-kernel.log

UPTO="${UPTO:-check}"
case "$UPTO" in setup|export|check) ;; *) die "UPTO must be setup, export or check" ;; esac
X="$WORKDIR/extra-tools"
mkdir -p "$X"

case "$LEAN_ARCH" in
  x86_64)  CHK_ASSET="lean-${CHECKER_LEAN_VERSION}-linux.tar.zst" ;;
  aarch64) CHK_ASSET="lean-${CHECKER_LEAN_VERSION}-linux_aarch64.tar.zst" ;;
esac
CHK_SHA_VAR="CHECKER_LEAN_SHA256_${LEAN_ARCH}"
CHK_HOME="$TC/${CHK_ASSET%.tar.zst}"
EXPORTER="$X/lean4export/.lake/build/bin/lean4export"
CONLECHE="$X/con-leche/.lake/build/bin/con-leche"

# pinned_checkout <url> <dir> <rev>
pinned_checkout() {
  local url="$1" dir="$2" rev="$3"
  [[ -d "$dir/.git" ]] || git clone --quiet "$url" "$dir"
  git -C "$dir" fetch --quiet origin "$rev" 2>/dev/null || git -C "$dir" fetch --quiet origin
  git -C "$dir" -c advice.detachedHead=false checkout --quiet --detach "$rev"
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$rev" ]] && ok "$(basename "$dir") at $rev" || bad "$(basename "$dir") not at $rev"
  [[ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ]] || bad "$(basename "$dir") has local modifications"
}

# ------------------------------------------------------------------ setup
log "Lean v$CHECKER_LEAN_VERSION (for con-leche)"
if [[ ! -x "$CHK_HOME/bin/lean" ]]; then
  if [[ ! -s "$TC/$CHK_ASSET" ]]; then
    curl -fsSL --retry 5 -o "$TC/$CHK_ASSET.partial" \
      "https://github.com/leanprover/lean4/releases/download/v${CHECKER_LEAN_VERSION}/$CHK_ASSET"
    mv -f "$TC/$CHK_ASSET.partial" "$TC/$CHK_ASSET"
  fi
  sha256_is "$TC/$CHK_ASSET" "${!CHK_SHA_VAR}" && ok "$CHK_ASSET matches pinned sha256" || { bad "$CHK_ASSET sha256 mismatch"; finish; }
  tar --use-compress-program=unzstd -xf "$TC/$CHK_ASSET" -C "$TC"
fi
v=$("$CHK_HOME/bin/lean" --version)
[[ "$v" == *"version $CHECKER_LEAN_VERSION,"* && "$v" == *"commit $CHECKER_LEAN_COMMIT"* ]] \
  && ok "lean v$CHECKER_LEAN_VERSION, commit $CHECKER_LEAN_COMMIT" || bad "unexpected: $v"

log "lean4export (built with Lean v$LEAN_VERSION)"
pinned_checkout "$LEAN4EXPORT_URL" "$X/lean4export" "$LEAN4EXPORT_REV"
if [[ ! -x "$EXPORTER" ]]; then
  (cd "$X/lean4export" && LEAN_NUM_THREADS="${SETUP_JOBS:-4}" nice -n 19 lake --keep-toolchain build 2>&1 | tail -3)
fi
[[ -x "$EXPORTER" ]] && ok "built $EXPORTER" || bad "lean4export build failed"

log "con-leche (built with Lean v$CHECKER_LEAN_VERSION)"
pinned_checkout "$CONLECHE_URL" "$X/con-leche" "$CONLECHE_REV"
if [[ ! -x "$CONLECHE" ]]; then
  (cd "$X/con-leche" && PATH="$CHK_HOME/bin:$PATH" LEAN_NUM_THREADS="${SETUP_JOBS:-4}" nice -n 19 \
     lake --keep-toolchain build con-leche 2>&1 | tail -3)
fi
[[ -x "$CONLECHE" ]] && ok "built $CONLECHE" || bad "con-leche build failed"
(( FAILS == 0 )) || finish

log "self-test: con-leche must accept a genuine export and reject a tampered one"
st=$(mktemp -d)
if LEAN_PATH= LEAN_ABORT_ON_PANIC=1 "$EXPORTER" Init -- Quot Quot.mk Quot.lift Quot.ind propext \
     Nat.le_refl Nat.lt_irrefl Nat.add_comm > "$st/ok.ndjson" 2> "$st/export.err" \
   && "$CONLECHE" --jobs=4 "$st/ok.ndjson" > "$st/ok.log" 2>&1 && grep -q 'accepted' "$st/ok.log"; then
  ok "genuine export of a few Init theorems accepted"
else
  bad "genuine export not accepted (see $st)"
fi
# Give the last exported theorem the proof of an earlier one with a different statement.
python3 -I - "$st/ok.ndjson" "$st/tampered.ndjson" <<'PY'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
thm = [(i, json.loads(l)) for i, l in enumerate(lines) if l.startswith('{"thm"')]
(i1, a) = thm[-1]
b = next(t for _, t in reversed(thm[:-1]) if t["thm"]["type"] != a["thm"]["type"])
a["thm"]["value"] = b["thm"]["value"]
lines[i1] = json.dumps(a, separators=(",", ":"))
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY
if "$CONLECHE" --jobs=4 "$st/tampered.ndjson" > "$st/tampered.log" 2>&1; then
  bad "con-leche ACCEPTED a tampered export (see $st)"
else
  ok "tampered export rejected: $(grep -m1 -oE 'invalid: [^[]*' "$st/tampered.log")"
  rm -rf "$st"
fi
(( FAILS == 0 )) || finish
[[ "$UPTO" == setup ]] && finish

# ------------------------------------------------------------------ export
trap 'echo "[interrupted; finishing up]"' INT TERM
if [[ "${EXPORT_SOURCE:-build}" == mit ]]; then
  # Check MIT's published export instead of exporting our own build. Needs no build and
  # ~50 GB RAM, so it suits machines too small to export (exporting needs the whole
  # project in memory plus the exporter's tables). Ties to our build only through the
  # .olean comparison (scripts/extra/compare_olean_manifest.py), not byte for byte.
  SOL="$OUT/solution-mit.ndjson"
  log "fetch MIT's published export of Main"
  if [[ -s "$SOL" && -s "$SOL.sha256" ]]; then
    echo "  reusing $SOL"
  else
    zst="$OUT/solution-mit.ndjson.zst"
    if [[ ! -s "$zst" ]] || ! sha256_is "$zst" "$REFERENCE_EXPORT_ZST_SHA256"; then
      curl -fsSL --retry 5 -C - -o "$zst" "$REFERENCE_EXPORT_URL"
    fi
    sha256_is "$zst" "$REFERENCE_EXPORT_ZST_SHA256" \
      && ok "compressed export matches MIT's published sha256 ($(stat -c %s "$zst") bytes)" \
      || { bad "compressed export sha256 mismatch"; finish; }
    zstd -d -q -f --long=30 -T0 -o "$SOL.partial" "$zst"
    mv -f "$SOL.partial" "$SOL"
    sha256sum "$SOL" | cut -d' ' -f1 > "$SOL.sha256"
  fi
  got=$(cat "$SOL.sha256")
  echo "  sha256 $got"
  [[ "$got" == "$REFERENCE_EXPORT_SHA256" ]] \
    && ok "unpacked export matches MIT's published sha256 ($(stat -c %s "$SOL") bytes)" \
    || { bad "unpacked export sha256 mismatch"; finish; }
else
need_project
need_max_map_count
[[ -d "$PROJ/.lake/build/lib" ]] || die "project not built; run scripts/05-build.sh"
if pgrep -x leanchecker >/dev/null && [[ "${FORCE:-0}" != 1 ]]; then
  die "leanchecker (step 7) is running; exporting now would slow it down. Wait, or set FORCE=1."
fi
SOL="$OUT/solution.ndjson"
log "export the proof of Main"
sha256_is "$REPO/expected/export-targets.txt" "$EXPORT_TARGETS_SHA256" \
  && ok "export targets match the pinned list" || { bad "expected/export-targets.txt changed"; finish; }
if [[ -s "$SOL" && -s "$SOL.sha256" && "${REEXPORT:-0}" != 1 ]]; then
  echo "  reusing existing $SOL (REEXPORT=1 to redo)"
else
  LP=$(cd "$PROJ" && lake --keep-toolchain env printenv LEAN_PATH)
  # A here-string, so `read` sees a trailing newline and does not fail under set -e.
  read -ra targets <<< "$(tr '\n' ' ' < "$REPO/expected/export-targets.txt")"
  (( ${#targets[@]} > 0 )) || die "no export targets"
  echo "  ${#targets[@]} export targets; LEAN_PATH has $(tr ':' '\n' <<< "$LP" | wc -l) entries"
  # Memory: the exporter holds the whole project plus its own tables (>30 GB here). With
  # 61 GiB RAM it stopped fitting at ~25 of ~62 GB and slowed to <1 MB/s, waiting on
  # disk for page faults; plan on >= 128 GB RAM, or use EXPORT_SOURCE=mit.
  start=$(date -u +%s)
  if (cd "$OUT" && LEAN_PATH="$LP" LEAN_ABORT_ON_PANIC=1 /usr/bin/time -f '  lean4export: wall %es, max RSS %M KB' \
        "$EXPORTER" Main -- "${targets[@]}" > "$SOL.partial"); then
    mv -f "$SOL.partial" "$SOL"
    ok "exported $(stat -c %s "$SOL") bytes in $(( $(date -u +%s) - start )) s"
  else
    bad "lean4export failed or was interrupted"; finish
  fi
  sha256sum "$SOL" | cut -d' ' -f1 > "$SOL.sha256"
fi
got=$(cat "$SOL.sha256")
echo "  sha256 $got"
if [[ "$got" == "$REFERENCE_EXPORT_SHA256" ]]; then
  ok "byte-identical to MIT's export: their nanoda and con-leche results apply to exactly this build"
else
  warn "differs from MIT's export ($REFERENCE_EXPORT_SHA256, $REFERENCE_EXPORT_SIZE bytes); the check below still applies to this build"
fi
fi
[[ "$UPTO" == export ]] && finish

# ------------------------------------------------------------------ check
if pgrep -x leanchecker >/dev/null && [[ "${FORCE:-0}" != 1 ]]; then
  die "leanchecker (step 7) is running; con-leche needs ~50 GB RAM. Wait, or set FORCE=1."
fi
CL_LOG="$OUT/con-leche-$(basename "$SOL" .ndjson).log"
log "con-leche on $(basename "$SOL") ($(nproc) workers)"
set +e
/usr/bin/time -v "$CONLECHE" --jobs="$(nproc)" --progress=5% "$SOL" > "$CL_LOG" 2>&1
rc=$?
set -e
grep -E 'accepted|rejected|error|done:|peak RSS' "$CL_LOG" | tail -6 | sed 's/^/  /' || true
if (( rc == 0 )) && grep -q 'accepted [0-9]* declarations' "$CL_LOG"; then
  ok "con-leche (independent kernel) accepts the exported proof"
else
  bad "con-leche did not accept (exit $rc); see $OUT/con-leche.log"
fi
finish
