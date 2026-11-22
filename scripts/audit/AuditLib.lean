/-
Audit helpers. Imports only Lean core, so it can be compiled and self-tested
(SelfTest.lean) before the 12-hour project build exists.

Every check either logs a PASS line or throws an error, which makes `lean`
exit non-zero. `06-audit.sh` relies on that exit status.
-/
import Lean

open Lean Elab Command Meta

namespace Audit

/-- The three axioms of standard Lean + Mathlib mathematics. -/
def standardAxioms : List Name := [``propext, ``Classical.choice, ``Quot.sound]

def getInfo (n : Name) : CommandElabM ConstantInfo := do
  match (← getEnv).find? n with
  | some ci => return ci
  | none => throwError "AUDIT FAIL: constant {n} not found"

/-- Module that defines `n` (`none` if defined in the current file). -/
def moduleOf? (n : Name) : CommandElabM (Option Name) := do
  let env ← getEnv
  return (env.getModuleIdxFor? n).map fun idx => env.header.moduleNames[idx.toNat]!

/-- Fail unless `n` depends on no axioms beyond `standardAxioms`. -/
def checkAxioms (n : Name) : CommandElabM Unit := do
  discard <| getInfo n
  let axs ← collectAxioms n
  let bad := axs.filter (!standardAxioms.contains ·)
  unless bad.isEmpty do
    throwError "AUDIT FAIL: {n} depends on non-standard axioms {bad.toList} (all: {axs.toList})"
  logInfo m!"PASS axioms  {n}: {axs.toList}"

/-- Fail unless `thm` is a theorem whose type is *syntactically* the constant `stmt`
(not merely definitionally equal to it). -/
def checkTheoremType (thm stmt : Name) : CommandElabM Unit := do
  let ci ← getInfo thm
  unless ci matches .thmInfo _ do
    throwError "AUDIT FAIL: {thm} is not a theorem"
  unless ci.levelParams.isEmpty do
    throwError "AUDIT FAIL: {thm} is universe-polymorphic"
  unless ci.type == mkConst stmt do
    throwError "AUDIT FAIL: type of {thm} is{indentExpr ci.type}\nexpected exactly the constant {stmt}"
  logInfo m!"PASS type    {thm} : {stmt}"

/-- Fail unless `n` is defined in module `mod`. -/
def checkDefinedIn (n mod : Name) : CommandElabM Unit := do
  discard <| getInfo n
  let m? ← moduleOf? n
  unless m? == some mod do
    throwError "AUDIT FAIL: {n} is defined in {m?}, expected {mod}"
  logInfo m!"PASS module  {n} is defined in {mod}"

/-- Body of a constant, including theorem bodies (`value?` hides those by default). -/
def bodyOf? (ci : ConstantInfo) : Option Expr := ci.value? (allowOpaque := true)

/-- Is `c` an auxiliary theorem `<something>._proof_N` that Lean generated for a proof
nested inside a definition? Lean may share one such theorem between several definitions
of the same file, so the owner is not necessarily the definition that uses it. -/
def isAuxProof (env : Environment) (c : Name) : Bool :=
  match c with
  | .str _ s => s.startsWith "_proof_" && (env.find? c matches some (.thmInfo _))
  | _ => false

/-- Inline every auxiliary nested-proof theorem in `e`, recovering the term as written.
Proofs are irrelevant to what a proposition means, so this never changes a statement;
it only removes generated names that differ between two copies of the same text. -/
partial def inlineAux (env : Environment) (e : Expr) : Expr :=
  e.replace fun
    | .const c us =>
      if isAuxProof env c then
        match env.find? c with
        | some ci => (bodyOf? ci).map fun v =>
            inlineAux env (v.instantiateLevelParams ci.levelParams us)
        | none => none
      else none
    | _ => none

/-- Fail unless definitions `actual` and `expected` are syntactically identical
(alpha-equivalence, no unfolding of definitions) once nested proofs are inlined.
`expected` is a copy, written in the audit file, of the statement text that a human
reviewed. A definitional-equality result is reported on failure, but it never passes. -/
def checkSameDefinition (actual expected : Name) : CommandElabM Unit := do
  let env ← getEnv
  let a ← getInfo actual
  let e ← getInfo expected
  unless a matches .defnInfo _ do
    throwError "AUDIT FAIL: {actual} is not a plain definition"
  let some av := a.value? | throwError "AUDIT FAIL: {actual} is not a definition"
  let some ev := e.value? | throwError "AUDIT FAIL: {expected} is not a definition"
  let (at', av') := (inlineAux env a.type, inlineAux env av)
  let (et', ev') := (inlineAux env e.type, inlineAux env ev)
  let nAux := (a.getUsedConstantsAsSet.toList.filter (isAuxProof env)).length
  if at' == et' && av' == ev' then
    logInfo m!"PASS defn    {actual} is syntactically identical to the reviewed text {expected}\
      {if nAux > 0 then s!" (after inlining {nAux} auxiliary proof(s))" else ""}"
  else
    let defeq ← liftTermElabM <| isDefEq av ev
    throwError "AUDIT FAIL: {actual} differs syntactically from {expected} (defeq: {defeq})\
      {indentExpr av'}\nvs{indentExpr ev'}"

/-- Fail unless every constant that `n` uses is defined in a module whose root is one
of `roots` (e.g. `Mathlib`, `Init`). Auxiliary nested-proof theorems are not accepted
as such: the check recurses into their types and bodies instead, so nothing can hide there. -/
def checkDepsFrom (n : Name) (roots : List Name) : CommandElabM Unit := do
  let env ← getEnv
  let uses (ci : ConstantInfo) : List Name :=
    (ci.type.getUsedConstants ++ ((bodyOf? ci).map (·.getUsedConstants)).getD #[]).toList
  let mut todo := uses (← getInfo n)
  let mut seen : NameSet := {}
  let mut nLib : Nat := 0
  while !todo.isEmpty do
    let c := todo.head!
    todo := todo.tail!
    if seen.contains c then continue
    seen := seen.insert c
    if isAuxProof env c then
      todo := uses (← getInfo c) ++ todo
      continue
    let some m ← moduleOf? c | throwError "AUDIT FAIL: {n} uses {c}, which is not from an imported module"
    unless roots.contains m.getRoot do
      throwError "AUDIT FAIL: {n} uses {c} from module {m}; allowed roots {roots}"
    nLib := nLib + 1
  logInfo m!"PASS deps    {n} uses only constants from {roots} ({nLib} constants)"

/-- Check each `(statement, reviewed copy, defining module)`: defined in that module (when
`checkModule` says so), identical to the reviewed copy, and built only from Mathlib/core. -/
def checkStatements (stmts : List (Name × Name × Name))
    (checkModule : Name → Bool := fun _ => true) : CommandElabM Unit := do
  for (n, r, mod) in stmts do
    if checkModule mod then checkDefinedIn n mod
    checkSameDefinition n r
    checkDepsFrom n [`Init, `Mathlib]

/-- Check each `(theorem, statement)`: defined in `mod`, has exactly that type, and
uses only the standard axioms. -/
def checkTheorems (thms : List (Name × Name)) (mod : Name) : CommandElabM Unit := do
  for (thm, stmt) in thms do
    checkDefinedIn thm mod
    checkTheoremType thm stmt
    checkAxioms thm

/-- Run `x` and fail if it does *not* fail. Used by the self-test. -/
def expectFailure (label : String) (x : CommandElabM Unit) : CommandElabM Unit := do
  let failed ← try x; pure false catch e => do
    logInfo m!"PASS selftest '{label}' rejected as expected: {e.toMessageData}"
    pure true
  unless failed do
    throwError "SELFTEST FAIL: '{label}' was accepted but must be rejected"

end Audit
