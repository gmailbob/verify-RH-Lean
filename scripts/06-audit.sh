#!/usr/bin/env bash
# Step 6: audit the statements and the final theorems.
#
# Stages (UPTO=selftest | statements | full, default full):
#   selftest    compile AuditLib.lean and run SelfTest.lean: shows the checks accept
#               good declarations and reject sorry, axioms, native_decide, defeq-only
#               types, statement drift and non-library constants. Needs step 1 only.
#   statements  compile Reviewed.lean against Mathlib, then elaborate the project's
#               Statements.lean on its own and check every statement against the
#               reviewed text. Needs step 4 only (minutes), so the statements can be
#               checked before the long build.
#   full        run ProofAudit.lean against the built project: statements again, plus
#               the type and axioms of every final theorem. Needs step 5.
# Outputs: $OUT/audit/selftest.txt, $OUT/audit/statements.txt, $OUT/audit.txt
source "$(dirname "$0")/lib.sh"
need_toolchain
log_to 06-audit.log

UPTO="${UPTO:-full}"
[[ "${SELFTEST_ONLY:-0}" == 1 ]] && UPTO=selftest
case "$UPTO" in selftest|statements|full) ;; *) die "UPTO must be selftest, statements or full" ;; esac

A="$OUT/audit"
mkdir -p "$A"
AUD="$REPO/scripts/audit"

# ------------------------------------------------------------------ selftest
log "compile AuditLib"
(cd "$AUD" && lean -R . -o "$A/AuditLib.olean" -i "$A/AuditLib.ilean" AuditLib.lean) \
  && ok "AuditLib compiled" || { bad "AuditLib failed to compile"; finish; }

log "self-test of the audit checks"
if (cd "$A" && LEAN_PATH="$A" lean "$AUD/SelfTest.lean") > "$A/selftest.txt" 2>&1 \
   && grep -q "SELFTEST COMPLETE" "$A/selftest.txt"; then
  grep -E '^PASS' "$A/selftest.txt" | sed 's/^/  /'
  ok "self-test: good declarations accepted, every cheat rejected"
else
  cat "$A/selftest.txt"; bad "self-test failed"; finish
fi
[[ "$UPTO" == selftest ]] && finish

# ------------------------------------------------------------------ statements
need_project
[[ -d "$PROJ/.lake/packages/mathlib/.lake/build" ]] || die "mathlib missing; run scripts/04-fetch-deps.sh"
LP=$(cd "$PROJ" && lake --keep-toolchain env printenv LEAN_PATH)

log "compile Reviewed.lean (the reviewed statement text) against Mathlib"
(cd "$AUD" && LEAN_PATH="$A:$LP" lean -R . -o "$A/Reviewed.olean" -i "$A/Reviewed.ilean" Reviewed.lean) \
  && ok "Reviewed compiled" || { bad "Reviewed.lean failed to compile"; finish; }

log "check Statements.lean against the reviewed text (before any build)"
stmts="$PROJ/src/Statements.lean"
imports=$(awk '/^[[:space:]]*$/ {next} /^import / {print $2; next} {exit}' "$stmts" | tr '\n' ' ')
if [[ "$imports" != "Mathlib " ]]; then
  bad "Statements.lean imports '$imports'; this stage expects exactly 'Mathlib'"; finish
fi
ok "Statements.lean imports only Mathlib"
pre="$A/StatementPrecheck.lean"
{
  echo "import Mathlib"
  echo "import AuditLib"
  echo "import Reviewed"
  echo
  echo "-- ---- body of the project's src/Statements.lean, verbatim ----"
  awk 'started {print; next} /^[[:space:]]*$/ {next} /^import / {next} {started=1; print}' "$stmts"
  echo "-- ---- end of Statements.lean ----"
  echo
  echo 'run_cmd Audit.checkStatements Reviewed.statements (checkModule := fun m => m != `Statements)'
  echo 'example : RiemannZetaZerosOnLine ↔ RiemannHypothesis := Iff.rfl'
  echo 'run_cmd Lean.logInfo "STATEMENT PRE-CHECK COMPLETE"'
} > "$pre"
if (cd "$A" && LEAN_PATH="$A:$LP" lean "$pre") > "$A/statements.txt" 2>&1 \
   && grep -q "STATEMENT PRE-CHECK COMPLETE" "$A/statements.txt" && ! grep -q "AUDIT FAIL" "$A/statements.txt"; then
  grep -E '^PASS' "$A/statements.txt" | sed 's/^/  /'
  ok "every statement matches the reviewed text and uses only Mathlib/core constants"
else
  cat "$A/statements.txt"; bad "statement pre-check failed"; finish
fi
[[ "$UPTO" == statements ]] && finish

# ------------------------------------------------------------------ full
[[ -d "$PROJ/.lake/build/lib" ]] || die "project not built; run scripts/05-build.sh"
need_max_map_count
log "audit the final theorems (imports the whole project; may take a while)"
set +e
(cd "$A" && LEAN_PATH="$A:$LP" /usr/bin/time -f 'wall %es, max RSS %M KB' \
   lean --tstack=400000 "$AUD/ProofAudit.lean") > "$OUT/audit.txt" 2>&1
rc=$?
set -e
cat "$OUT/audit.txt"
if (( rc == 0 )) && grep -q "AUDIT COMPLETE" "$OUT/audit.txt" && ! grep -q "AUDIT FAIL" "$OUT/audit.txt"; then
  ok "all audit checks passed"
else
  bad "audit failed (exit $rc); see $OUT/audit.txt"
fi
finish
