/-
Self-test for AuditLib: shows the checks accept good declarations and reject
each kind of cheat they are meant to catch. Needs only Lean core.
Run by 06-audit.sh before the real audit; can also be run right after step 1.
-/
import AuditLib

open Lean Elab Command Audit

-- Positive cases
theorem good_noAxioms (a b : Nat) : a + b = b + a := Nat.add_comm a b
theorem good_classical (p : Prop) : p ∨ ¬p := Classical.em p
def MyStmt : Prop := ∀ n : Nat, n + 0 = n
theorem good_typed : MyStmt := fun _ => rfl
def MyStmtCopy : Prop := ∀ n : Nat, n + 0 = n

run_cmd checkAxioms ``good_noAxioms
run_cmd checkAxioms ``good_classical
run_cmd checkTheoremType ``good_typed ``MyStmt
run_cmd checkSameDefinition ``MyStmt ``MyStmtCopy
run_cmd checkDefinedIn ``Nat.add_comm `Init.Data.Nat.Basic
run_cmd checkDepsFrom ``MyStmt [`Init]

-- Statements with nested proofs. Lean abstracts the proof into `PStmt._proof_1`, and the
-- copy *reuses* that same auxiliary. A copy in another file would get its own. Both
-- situations must compare equal, and deps must look through auxiliaries.
def PStmt : Prop := (⟨0, by decide⟩ : Fin 1) = ⟨0, by decide⟩
def PStmtCopy : Prop := (⟨0, by decide⟩ : Fin 1) = ⟨0, by decide⟩
def usesAux (n : Name) : CommandElabM Bool := do
  let env ← getEnv
  let some ci := env.find? n | throwError "missing {n}"
  return ci.getUsedConstantsAsSet.toList.any (isAuxProof env)
run_cmd do
  unless (← usesAux ``PStmt) && (← usesAux ``PStmtCopy) do
    throwError "SELFTEST FAIL: expected nested-proof auxiliaries; test is not meaningful"
run_cmd checkSameDefinition ``PStmt ``PStmtCopy
run_cmd checkDepsFrom ``PStmt [`Init]

-- Negative cases: each must be rejected
set_option warn.sorry false in
theorem bad_sorry : False := sorry
axiom myAxiom : False
theorem bad_axiom : False := myAxiom
theorem bad_native : 123456789 * 987654321 = 121932631112635269 := by native_decide
theorem bad_type : ∀ n : Nat, n + 0 = n := fun _ => rfl     -- defeq to MyStmt, not syntactically
def MyStmtDrift : Prop := ∀ n : Nat, 0 + n = n
def UsesLocal : Prop := MyStmt ∧ True
theorem localLt : 0 < 3 := by decide
-- The local lemma is hidden inside an auxiliary proof; deps must still find it. The
-- proposition `0 < 3` is proved nowhere else in this file, so Lean cannot replace the
-- proof with a shared auxiliary (it shares auxiliaries by the proposition they prove).
def HidesLocal : Prop :=
  (⟨0, Nat.lt_of_lt_of_le localLt (Nat.le_refl 3)⟩ : Fin 3) = ⟨0, Nat.lt_of_lt_of_le localLt (Nat.le_refl 3)⟩
def PStmtDrift : Prop := (⟨0, by decide⟩ : Fin 2) = ⟨0, by decide⟩

run_cmd expectFailure "sorry"         (checkAxioms ``bad_sorry)
run_cmd expectFailure "custom axiom"  (checkAxioms ``bad_axiom)
run_cmd expectFailure "native_decide" (checkAxioms ``bad_native)
run_cmd expectFailure "type only defeq to the statement" (checkTheoremType ``bad_type ``MyStmt)
run_cmd expectFailure "statement drift" (checkSameDefinition ``MyStmt ``MyStmtDrift)
run_cmd expectFailure "wrong module" (checkDefinedIn ``Nat.add_comm `Mathlib.Foo)
run_cmd expectFailure "statement uses a non-library constant" (checkDepsFrom ``UsesLocal [`Init])
run_cmd do
  let env ← getEnv
  let some ci := env.find? ``HidesLocal | throwError "missing"
  let auxes := ci.getUsedConstantsAsSet.toList.filter (isAuxProof env)
  let hidden := auxes.any fun c => match env.find? c >>= bodyOf? with
    | some b => b.getUsedConstants.contains ``localLt
    | none => false
  if ci.getUsedConstantsAsSet.contains ``localLt || !hidden then
    throwError "SELFTEST FAIL: localLt is not hidden inside an auxiliary; test is not meaningful"
run_cmd expectFailure "local lemma hidden in an auxiliary proof" (checkDepsFrom ``HidesLocal [`Init])
run_cmd expectFailure "drift in a statement with nested proofs" (checkSameDefinition ``PStmt ``PStmtDrift)
run_cmd expectFailure "missing constant" (checkAxioms `does.not.exist)

run_cmd logInfo "SELFTEST COMPLETE"
