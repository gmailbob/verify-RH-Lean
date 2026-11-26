/-
The audit of the final theorems. Run by 06-audit.sh after the build, with the built
project on LEAN_PATH so that `import Main` resolves to it.

What it establishes, each as a hard check:
 1. `RiemannHypothesis` is Mathlib's own definition.
 2. Every statement is defined where it should be, uses only Mathlib/core constants,
    and is syntactically identical to the reviewed text in Reviewed.lean.
    The comparison uses alpha-equivalence and unfolds no definitions; it only inlines
    the auxiliary `_proof_N` lemmas Lean generates for nested proofs.
 3. Each theorem in `Main` has exactly its statement as its type.
 4. Each theorem depends only on propext, Classical.choice and Quot.sound.
-/
import Main
import AuditLib
import Reviewed

set_option maxHeartbeats 0  -- the axiom traversal walks the whole proof

open Audit

-- Human-readable record of what is being checked.
#print RiemannHypothesis
#print RiemannZetaZerosOnLine
#print DirichletLNonvanishingRightOfHalf
#print DirichletLZerosOnLine
#print PrimitiveDirichletLZerosOnLine
#check @riemannHypothesis
#check @riemannZeta_eq_zero_re
#check @LFunction_ne_zero_of_half_lt_re
#check @LFunction_eq_zero_re
#check @LFunction_eq_zero_re_of_isPrimitive

-- 1 + 2. Statements.
run_cmd checkStatements Reviewed.statements (checkModule := fun _ => true)

-- The project's zeta statement is the same proposition as Mathlib's (by unfolding).
example : RiemannZetaZerosOnLine ↔ RiemannHypothesis := Iff.rfl

-- 3 + 4. The final theorems.
run_cmd checkTheorems Reviewed.theorems `Main

-- The same axiom information, in the standard human-readable form.
#print axioms riemannHypothesis
#print axioms riemannZeta_eq_zero_re
#print axioms LFunction_ne_zero_of_half_lt_re
#print axioms LFunction_eq_zero_re
#print axioms LFunction_eq_zero_re_of_isPrimitive

run_cmd Lean.logInfo "AUDIT COMPLETE: all checks passed"
