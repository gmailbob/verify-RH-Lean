/-
Optional exploration, not a verification step: print the top of the proof tree.

Starting from the five final theorems, list the project declarations each one uses
directly (looking through Lean's generated auxiliaries such as `_proof_N`), with their
statements, down to a fixed depth. Library constants (Lean core, Mathlib, ...) are not
expanded. Run against the built project, e.g.:
  LEAN_PATH=$(cd $PROJ && lake env printenv LEAN_PATH) lean ProofTree.lean > proof-tree.txt
-/
import Main

open Lean Elab Command Meta

namespace ProofTree

def libraryRoots : List Name :=
  [`Init, `Lean, `Std, `Lake, `Mathlib, `Batteries, `Aesop, `Qq, `ProofWidgets, `Plausible,
   `LeanSearchClient, `ImportGraph, `Cli]

def maxDepth : Nat := 4
def maxChildren : Nat := 30
def maxTypeChars : Nat := 400

def bodyOf? (ci : ConstantInfo) : Option Expr := ci.value? (allowOpaque := true)

def isLibrary (env : Environment) (c : Name) : Bool :=
  match env.getModuleIdxFor? c with
  | some idx => libraryRoots.contains (env.header.moduleNames[idx.toNat]!).getRoot
  | none => false

/-- Generated helpers we look through rather than print. -/
def isAux (c : Name) : Bool := c.isInternalDetail || c.isInternal

/-- Project constants used directly by `c`, looking through auxiliaries. -/
partial def directDeps (env : Environment) (c : Name) : Array Name := Id.run do
  let mut out : Array Name := #[]
  let mut seen : NameSet := {}
  let mut todo : List Name := [c]
  let mut first := true
  while !todo.isEmpty do
    let n := todo.head!
    todo := todo.tail!
    let some ci := env.find? n | continue
    let used := ci.type.getUsedConstants ++ ((bodyOf? ci).map (·.getUsedConstants)).getD #[]
    for u in used do
      if u == c || seen.contains u then continue
      seen := seen.insert u
      if isLibrary env u then continue
      if isAux u then todo := u :: todo
      else out := out.push u
    first := false
  return out

def moduleName (env : Environment) (c : Name) : String :=
  match env.getModuleIdxFor? c with
  | some idx => toString env.header.moduleNames[idx.toNat]!
  | none => "?"

def kind : ConstantInfo → String
  | .thmInfo _ => "theorem" | .defnInfo _ => "def" | .axiomInfo _ => "AXIOM"
  | .opaqueInfo _ => "opaque" | .inductInfo _ => "inductive" | .ctorInfo _ => "ctor"
  | .recInfo _ => "recursor" | .quotInfo _ => "quot"

/-- Collapse a pretty-printed term onto one line and truncate it. -/
def oneLine (s : String) : String := Id.run do
  let mut out : List Char := []
  let mut prevSpace := false
  for ch in s.toList do
    let ch := if ch == '\n' then ' ' else ch
    if ch == ' ' && prevSpace then continue
    prevSpace := ch == ' '
    out := ch :: out
  let cs := out.reverse
  if cs.length > maxTypeChars then String.ofList (cs.take maxTypeChars) ++ " …" else String.ofList cs

partial def visit (c : Name) (depth : Nat) (printed : IO.Ref NameSet) : CommandElabM Unit := do
  let env ← getEnv
  let some ci := env.find? c | return
  let pad := String.ofList (List.replicate (2 * depth) ' ')
  if (← printed.get).contains c then
    IO.println s!"{pad}- {c}  (see above)"
    return
  printed.modify (·.insert c)
  let ty ← liftTermElabM <| do return toString (← ppExpr ci.type)
  let deps := directDeps env c
  IO.println s!"{pad}- {kind ci} {c}  [{moduleName env c}]  ({deps.size} project deps)"
  IO.println s!"{pad}    : {oneLine ty}"
  if depth < maxDepth then
    for d in deps[:maxChildren] do
      visit d (depth + 1) printed
    if deps.size > maxChildren then
      IO.println s!"{pad}  … {deps.size - maxChildren} more"

end ProofTree

set_option maxHeartbeats 0 in
run_cmd do
  let printed ← IO.mkRef ({} : NameSet)
  for root in [``riemannHypothesis, ``riemannZeta_eq_zero_re, ``LFunction_ne_zero_of_half_lt_re,
               ``LFunction_eq_zero_re, ``LFunction_eq_zero_re_of_isPrimitive] do
    ProofTree.visit root 0 printed
    IO.println ""
