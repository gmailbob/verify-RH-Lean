#!/usr/bin/env bash
# Step 9: check the proof with independently written kernels.
#
# Steps 5 and 7 both trust Lean's own kernel. This step exports the proof of your own build
# and has three separate kernel implementations check the export: con-leche, con-ron and
# nanoda. A bug in Lean's kernel would not carry over to them. All four tools (the exporter
# and the three checkers) are the binaries shipped in the Lean release that step 1 verified
# against its pinned hash, so nothing else is downloaded.
#
# The checkers also police axioms. nanoda is given an allow-list of propext,
# Classical.choice and Quot.sound, and stops at any other axiom in the export. con-leche
# and con-ron decline a file that declares any other axiom or uses sorryAx.
#
# Stages (UPTO=setup | export | check, default check = all three):
#   setup   self-test on a few theorems of Lean's core library: every checker must accept
#           a genuine export and reject a tampered one, and nanoda must refuse an export
#           that uses an axiom outside its allow-list. Seconds; needs step 1 only.
#   export  leanexport Main -- <expected/export-targets.txt>  ->  $OUT/solution.ndjson
#           The five final theorems with everything they depend on, Mathlib included.
#   check   con-leche, con-ron and nanoda check the export, one after another.
#           Exit codes of con-leche and con-ron: 0 accepted, 1 rejected, 2 declined (a
#           construct the checker does not support; not a verdict), 3 malformed/internal.
#           The step passes if no checker rejects and at least one accepts.
# Export and check load the whole proof; they refuse to start while leanchecker (step 7) runs,
# unless FORCE=1. With enough memory the two can run side by side: the replay uses one core,
# so start this step with e.g. FORCE=1 CHECK_JOBS=$(( $(nproc) - 2 )) to leave it room.
# An existing solution.ndjson is reused unless REEXPORT=1.
source "$(dirname "$0")/lib.sh"
need_toolchain
log_to 09-independent-kernel.log

UPTO="${UPTO:-check}"
case "$UPTO" in setup|export|check) ;; *) die "UPTO must be setup, export or check" ;; esac
NCPU="${CHECK_JOBS:-$(nproc)}"   # worker threads for the checkers
# Options for con-leche and con-ron. The self-test uses the same ones as the real run, so a
# wrong option shows up there. --progress takes a number of declarations, not a percentage.
CL_OPTS=(--progress=20000)

log "tools shipped with Lean v$LEAN_VERSION"
for t in leanexport con-leche con-ron nanoda_bin; do
  [[ "$(command -v "$t")" == "$LEAN_HOME/bin/$t" ]] && ok "$t" || bad "$t not found in $LEAN_HOME/bin"
done
(( FAILS == 0 )) || finish

# nanoda_config <export-file> <config-out> <threads> <axiom> [<axiom> ...]
# nanoda parses the export on one thread and then checks on <threads> threads.
nanoda_config() {
  python3 -I - "$@" <<'PY'
import json, sys
export, out, threads, axioms = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
json.dump({"export_file_path": export, "use_stdin": False, "permitted_axioms": axioms,
           "unpermitted_axiom_hard_error": True, "nat_extension": True, "string_extension": True,
           "num_threads": threads, "print_success_message": True}, open(out, "w"), indent=1)
PY
}
STD_AXIOMS=(propext Classical.choice Quot.sound)

# ------------------------------------------------------------------ setup
log "self-test: each checker must accept a genuine export and reject a tampered one"
st=$(mktemp -d)
if ! LEAN_PATH= LEAN_ABORT_ON_PANIC=1 leanexport Init -- Quot Quot.mk Quot.lift Quot.ind propext \
       Nat.le_refl Nat.lt_irrefl Nat.add_comm > "$st/ok.ndjson" 2> "$st/export.err"; then
  bad "leanexport failed on Init (see $st)"; finish
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
for c in con-leche con-ron; do
  set +e
  "$c" --jobs=4 "${CL_OPTS[@]}" "$st/ok.ndjson" > "$st/$c-ok.log" 2>&1; rc_ok=$?
  "$c" --jobs=4 "${CL_OPTS[@]}" "$st/tampered.ndjson" > "$st/$c-tampered.log" 2>&1; rc_bad=$?
  set -e
  (( rc_ok == 0 )) && ok "$c accepts the genuine export" || bad "$c did not accept the genuine export (exit $rc_ok)"
  (( rc_bad == 1 )) && ok "$c rejects the tampered export: $(grep -m1 -oE '(invalid|rejected): [^[]*' "$st/$c-tampered.log")" \
    || bad "$c did not reject the tampered export (exit $rc_bad)"
done
nanoda_config "$st/ok.ndjson" "$st/n-ok.json" 4 "${STD_AXIOMS[@]}"
nanoda_config "$st/tampered.ndjson" "$st/n-tampered.json" 4 "${STD_AXIOMS[@]}"
nanoda_config "$st/ok.ndjson" "$st/n-noaxiom.json" 4 Classical.choice Quot.sound   # propext not allowed
set +e
nanoda_bin "$st/n-ok.json" > "$st/nanoda-ok.log" 2>&1; rc_ok=$?
nanoda_bin "$st/n-tampered.json" > "$st/nanoda-tampered.log" 2>&1; rc_bad=$?
nanoda_bin "$st/n-noaxiom.json" > "$st/nanoda-noaxiom.log" 2>&1; rc_ax=$?
set -e
(( rc_ok == 0 )) && grep -q 'no typechecker errors' "$st/nanoda-ok.log" && ok "nanoda accepts the genuine export" \
  || bad "nanoda did not accept the genuine export (exit $rc_ok)"
(( rc_bad != 0 )) && ok "nanoda rejects the tampered export (exit $rc_bad)" || bad "nanoda ACCEPTED the tampered export"
(( rc_ax != 0 )) && ok "nanoda refuses an export that uses an axiom outside the allow-list (exit $rc_ax)" \
  || bad "nanoda accepted an export using an axiom outside the allow-list"
if (( FAILS == 0 )); then rm -rf "${st:?}"; else echo "  self-test files kept in $st"; finish; fi
[[ "$UPTO" == setup ]] && finish

# ------------------------------------------------------------------ export
trap 'echo "[interrupted; finishing up]"' INT TERM
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
  # Memory: the exporter holds every .olean it reads plus its own tables. If they do not
  # fit in RAM it slows down sharply (it waits on disk for page faults; more swap does not help).
  start=$(date -u +%s)
  if (cd "$OUT" && LEAN_PATH="$LP" LEAN_ABORT_ON_PANIC=1 /usr/bin/time -f '  leanexport: wall %es, max RSS %M KB' \
        leanexport Main -- "${targets[@]}" > "$SOL.partial"); then
    mv -f "$SOL.partial" "$SOL"
    ok "exported $(stat -c %s "$SOL") bytes in $(( $(date -u +%s) - start )) s"
  else
    bad "leanexport failed or was interrupted"; finish
  fi
  sha256sum "$SOL" | cut -d' ' -f1 > "$SOL.sha256"
fi
echo "  sha256 $(cat "$SOL.sha256")  ($(stat -c %s "$SOL") bytes)"
[[ "$UPTO" == export ]] && finish

# ------------------------------------------------------------------ check
if pgrep -x leanchecker >/dev/null && [[ "${FORCE:-0}" != 1 ]]; then
  die "leanchecker (step 7) is running; the checkers would compete with it for memory. Wait, or set FORCE=1."
fi
accepts=0
for c in con-leche con-ron; do
  log "$c on $(basename "$SOL") ($NCPU workers)"
  set +e
  /usr/bin/time -v "$c" --jobs="$NCPU" "${CL_OPTS[@]}" "$SOL" > "$OUT/$c.log" 2>&1
  rc=$?
  set -e
  grep -E "^$c: (accepted|invalid|rejected|declin|done:|--)|peak RSS|Elapsed" "$OUT/$c.log" | tail -5 | sed 's/^/  /' || true
  case $rc in
    0) if grep -q 'accepted [0-9]* declarations' "$OUT/$c.log"; then ok "$c accepts the exported proof"; accepts=$((accepts + 1))
       else bad "$c exited 0 without an acceptance line; see $OUT/$c.log"; fi ;;
    2) warn "$c declined (a construct it does not support; not a verdict on the proof); see $OUT/$c.log" ;;
    3) bad "$c stopped with a usage, input or internal error (exit 3; not a verdict on the proof); see $OUT/$c.log" ;;
    *) bad "$c did not accept (exit $rc); see $OUT/$c.log" ;;
  esac
done

log "nanoda on $(basename "$SOL") ($NCPU threads; allow-list: ${STD_AXIOMS[*]})"
nanoda_config "$SOL" "$OUT/nanoda-config.json" "$NCPU" "${STD_AXIOMS[@]}"
set +e
/usr/bin/time -v nanoda_bin "$OUT/nanoda-config.json" > "$OUT/nanoda.log" 2>&1
rc=$?
set -e
grep -E 'Checked [0-9]+ declarations|Elapsed|Maximum resident' "$OUT/nanoda.log" | sed 's/^/  /' || true
if (( rc == 0 )) && grep -q 'no typechecker errors' "$OUT/nanoda.log"; then
  ok "nanoda accepts the exported proof, with no axiom outside the allow-list"; accepts=$((accepts + 1))
else
  bad "nanoda did not accept (exit $rc); see $OUT/nanoda.log"
fi

(( accepts >= 1 )) && ok "$accepts of 3 independent checkers accept; none rejects" || bad "no independent checker accepted the export"
finish
