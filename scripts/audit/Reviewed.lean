/-
THE PART A HUMAN MUST READ.

The reviewed text of every statement the audit checks, plus the list of which
theorem must prove which statement. The audit then checks mechanically that the
project's definitions are syntactically identical to these, so this text is exactly
what the theorems mean. Compare it with the mathematics yourself.

Imports only Mathlib. Compiled by 06-audit.sh after step 4.
-/
import Mathlib

namespace Reviewed

/-- Mathlib's statement of the Riemann hypothesis, copied from
`Mathlib/NumberTheory/LSeries/RiemannZeta.lean` at the pinned mathlib revision:
every zero of ζ that is not a trivial zero −2(n+1), and is not s = 1, has real part 1/2. -/
def RiemannHypothesis : Prop :=
  ∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2

/-- The project's restatement of RH (from `src/Statements.lean`). -/
def RiemannZetaZerosOnLine : Prop :=
  ∀ s : ℂ, riemannZeta s = 0 → (¬∃ n : ℕ, s = -2 * ((n : ℂ) + 1)) → s ≠ 1 → s.re = 1 / 2

/-- GRH, right half-plane: L(χ, s) ≠ 0 for Re s > 1/2, for every Dirichlet character χ
of every modulus N ≥ 1, except at the pole s = 1 of the trivial character. -/
def DirichletLNonvanishingRightOfHalf : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N) (s : ℂ),
    1 / 2 < s.re → (χ ≠ 1 ∨ s ≠ 1) → DirichletCharacter.LFunction χ s ≠ 0

/-- GRH for all Dirichlet characters: zeros in the strip 0 < Re s < 1 lie on Re s = 1/2. -/
def DirichletLZerosOnLine : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N) (s : ℂ),
    0 < s.re → s.re < 1 → DirichletCharacter.LFunction χ s = 0 → s.re = 1 / 2

/-- GRH for primitive Dirichlet characters. -/
def PrimitiveDirichletLZerosOnLine : Prop :=
  ∀ (N : ℕ) [NeZero N] (χ : DirichletCharacter ℂ N), χ.IsPrimitive →
    ∀ s : ℂ, 0 < s.re → s.re < 1 → DirichletCharacter.LFunction χ s = 0 → s.re = 1 / 2

open Lean in
/-- (statement in the environment, reviewed copy above, module that must define it) -/
def statements : List (Name × Name × Name) :=
  [(`RiemannHypothesis, `Reviewed.RiemannHypothesis, `Mathlib.NumberTheory.LSeries.RiemannZeta),
   (`RiemannZetaZerosOnLine, `Reviewed.RiemannZetaZerosOnLine, `Statements),
   (`DirichletLNonvanishingRightOfHalf, `Reviewed.DirichletLNonvanishingRightOfHalf, `Statements),
   (`DirichletLZerosOnLine, `Reviewed.DirichletLZerosOnLine, `Statements),
   (`PrimitiveDirichletLZerosOnLine, `Reviewed.PrimitiveDirichletLZerosOnLine, `Statements)]

open Lean in
/-- (final theorem in `Main`, the statement that must be exactly its type) -/
def theorems : List (Name × Name) :=
  [(`riemannHypothesis, `RiemannHypothesis),
   (`riemannZeta_eq_zero_re, `RiemannZetaZerosOnLine),
   (`LFunction_ne_zero_of_half_lt_re, `DirichletLNonvanishingRightOfHalf),
   (`LFunction_eq_zero_re, `DirichletLZerosOnLine),
   (`LFunction_eq_zero_re_of_isPrimitive, `PrimitiveDirichletLZerosOnLine)]

end Reviewed
