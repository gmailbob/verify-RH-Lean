/-
depgraph: export the declaration-level dependency graph of a built Lean project.

Optional exploration tool, not a verification step. Compiled to a native executable
(see build.sh): interpreted Lean is far too slow for millions of declarations.

Usage:  depgraph <out-dir> <root-module> [library-root ...]
  LEAN_PATH must make <root-module> importable (e.g. `lake env printenv LEAN_PATH`).
  Library roots (default: Lean core, Mathlib and its dependencies) are not nodes.

Writes to <out-dir>:
  nodes.tsv   one line per node:  index \t name \t kind \t module \t user
              kind: t theorem, d def, i inductive, c constructor, r recursor, o opaque,
                    a axiom, q quot.  user: 1 if a user-written declaration (not generated).
  edges.bin   "DGR1", u32 N, then for each node in index order: u32 deg, deg x u32 targets.
              Little-endian. Edge i -> j: declaration i mentions j in its type or body
              (theorem bodies included); an inductive also points to its constructors.
              Edges to library constants are dropped. No self-edges, no duplicates.
  meta.txt    counts, settings, timings, self-check result.

Self-check: after writing, the files are read back and, for a sample of nodes, the
edges are recomputed by an independent route (Expr.foldConsts instead of
Expr.getUsedConstants) and compared. The exit status is non-zero on any mismatch.
-/
import Lean

open Lean

namespace DepGraph

def defaultLibraryRoots : List Name :=
  [`Init, `Lean, `Std, `Lake, `Mathlib, `Batteries, `Aesop, `Qq, `ProofWidgets, `Plausible,
   `LeanSearchClient, `ImportGraph, `Cli]

def kindChar : ConstantInfo → Char
  | .thmInfo _ => 't' | .defnInfo _ => 'd' | .axiomInfo _ => 'a' | .opaqueInfo _ => 'o'
  | .inductInfo _ => 'i' | .ctorInfo _ => 'c' | .recInfo _ => 'r' | .quotInfo _ => 'q'

/-- Last-component suffixes of declarations Lean generates automatically. -/
def generatedSuffixes : List String :=
  ["eq_def", "eq_unfold", "inj", "injEq", "sizeOf_spec", "ctorIdx", "toCtorIdx", "noConfusionType",
   "noConfusion", "casesOn", "recOn", "rec", "below", "brecOn", "binductionOn", "ibelow", "induct",
   "mutual_induct", "fun_cases", "elim", "ext_iff"]

/-- A declaration a person wrote (theorem, def, inductive, opaque, axiom), not one Lean generated. -/
def isUserFacing (env : Environment) (n : Name) (ci : ConstantInfo) : Bool :=
  let kindOk := match ci with
    | .thmInfo _ | .defnInfo _ | .inductInfo _ | .opaqueInfo _ | .axiomInfo _ => true
    | _ => false
  let suffixOk := match n with
    | .str _ s => !generatedSuffixes.contains s
    | _ => false
  kindOk && suffixOk && !n.isInternalDetail && !isAuxRecursor env n && !isNoConfusion env n
    && !Meta.isMatcherCore env n

def sanitize (s : String) : String := (s.replace "\t" "\\t").replace "\n" "\\n"

@[inline] def pushU32 (b : ByteArray) (x : UInt32) : ByteArray :=
  ((b.push x.toUInt8).push (x >>> 8).toUInt8 |>.push (x >>> 16).toUInt8) |>.push (x >>> 24).toUInt8

def readU32 (b : ByteArray) (o : Nat) : UInt32 :=
  b[o]!.toUInt32 ||| (b[o+1]!.toUInt32 <<< 8) ||| (b[o+2]!.toUInt32 <<< 16) ||| (b[o+3]!.toUInt32 <<< 24)

/-- Raw dependency names of a declaration: type, body (theorems included), constructors. -/
def rawDeps (ci : ConstantInfo) : Array Name := Id.run do
  let mut used := ci.type.getUsedConstants
  if let some v := ci.value? (allowOpaque := true) then used := used ++ v.getUsedConstants
  if let .inductInfo v := ci then used := used ++ v.ctors.toArray
  return used

/-- The same set, computed by a different traversal, for the self-check. -/
def rawDepsAlt (ci : ConstantInfo) : NameSet := Id.run do
  let mut s : NameSet := ci.type.foldConsts {} fun n acc => acc.insert n
  if let some v := ci.value? (allowOpaque := true) then s := v.foldConsts s fun n acc => acc.insert n
  if let .inductInfo v := ci then s := v.ctors.foldl (·.insert ·) s
  return s

def targetsOf (index : Std.HashMap Name UInt32) (i : UInt32) (used : Array Name) : Array UInt32 := Id.run do
  let mut ts : Array UInt32 := #[]
  for u in used do
    if let some j := index[u]? then
      if j != i then ts := ts.push j
  let sorted := ts.qsort (· < ·)
  let mut out : Array UInt32 := #[]
  for j in sorted do
    if out.back? != some j then out := out.push j
  return out

end DepGraph

open DepGraph in
def main (args : List String) : IO UInt32 := do
  let (outDir, rootMod, libs) ← match args with
    | o :: r :: ls => pure ((o : System.FilePath), r.toName, if ls.isEmpty then defaultLibraryRoots else ls.map String.toName)
    | _ => throw <| IO.userError "usage: depgraph <out-dir> <root-module> [library-root ...]"
  IO.FS.createDirAll outDir
  initSearchPath (← findSysroot)
  let t0 ← IO.monoMsNow
  let env ← importModules #[{ module := rootMod }] {} (trustLevel := 1024)
  let t1 ← IO.monoMsNow
  let nConsts := env.constants.fold (init := 0) fun acc _ _ => acc + 1
  IO.println s!"imported {rootMod}: {env.header.moduleNames.size} modules, {nConsts} constants, {(t1 - t0) / 1000} s"

  let moduleOf (n : Name) : Option Name :=
    (env.getModuleIdxFor? n).map fun idx => env.header.moduleNames[idx.toNat]!
  let isProject (n : Name) : Bool :=
    match moduleOf n with
    | some m => !libs.contains m.getRoot
    | none => false
  -- index the project's constants (single accumulators, so updates stay in place)
  -- Node order: module by module, each in the order its .olean stores the declarations.
  -- Visiting them in that order makes page faults on the memory-mapped .olean files mostly
  -- sequential. Hash order (env.constants.fold) jumps randomly between ~175k files and is
  -- limited by disk latency when the files do not fit in RAM (~1 ms per fault on EBS).
  -- Lean can generate the same on-demand lemma (e.g. `f.eq_1`, `congr_simp`) in more
  -- than one module, so a name may appear in several modules' lists; keep the first.
  let mut names : Array Name := #[]
  let mut index : Std.HashMap Name UInt32 := {}
  for i in [0:env.header.moduleNames.size] do
    if libs.contains (env.header.moduleNames[i]!).getRoot then continue
    for n in (env.header.moduleData[i]!).constNames do
      if isProject n && !index.contains n then
        index := index.insert n names.size.toUInt32
        names := names.push n
  let N := names.size
  let tIdx ← IO.monoMsNow
  IO.println s!"project nodes: {N} (indexed in {(tIdx - t1) / 1000} s)"

  -- nodes.tsv
  let hn ← IO.FS.Handle.mk (outDir / "nodes.tsv") .write
  let mut users := 0
  let mut lines : Array String := #[]
  for i in [0:N] do
    let n := names[i]!
    let some ci := env.find? n | throw <| IO.userError s!"missing {n}"
    let u := isUserFacing env n ci
    if u then users := users + 1
    lines := lines.push s!"{i}\t{sanitize (toString n)}\t{kindChar ci}\t{(moduleOf n).getD `«?»}\t{if u then 1 else 0}\n"
    if lines.size ≥ 100000 then
      hn.putStr (String.join lines.toList); lines := #[]
  hn.putStr (String.join lines.toList)
  hn.flush
  let tNodes ← IO.monoMsNow
  IO.println s!"nodes.tsv written ({(tNodes - t1) / 1000} s)"

  -- edges.bin
  let he ← IO.FS.Handle.mk (outDir / "edges.bin") .write
  he.write ("DGR1".toUTF8)
  he.write (pushU32 .empty N.toUInt32)
  let mut buf := ByteArray.empty
  let mut nEdges := 0
  for i in [0:N] do
    let some ci := env.find? names[i]! | throw <| IO.userError "missing"
    let ts := targetsOf index i.toUInt32 (rawDeps ci)
    buf := pushU32 buf ts.size.toUInt32
    for j in ts do buf := pushU32 buf j
    nEdges := nEdges + ts.size
    if buf.size ≥ (1 <<< 24) then
      he.write buf; buf := .empty
  he.write buf
  he.flush
  let t2 ← IO.monoMsNow
  IO.println s!"edges: {nEdges}; user-written nodes: {users}; export {(t2 - t1) / 1000} s"

  -- self-check: read back and compare a sample against an independent traversal
  let bytes ← IO.FS.readBinFile (outDir / "edges.bin")
  let mut ok := String.fromUTF8! (bytes.extract 0 4) == "DGR1" && readU32 bytes 4 == N.toUInt32
  let mut off := 8
  let mut checked := 0
  let mut bad := 0
  let stride := max 1 (N / 2000)
  let tsv ← IO.FS.lines (outDir / "nodes.tsv")
  ok := ok && tsv.size == N
  for i in [0:N] do
    let deg := (readU32 bytes off).toNat
    off := off + 4
    if i % stride == 0 then
      let fromFile := (List.range deg).toArray.map fun k => readU32 bytes (off + 4 * k)
      let some ci := env.find? names[i]! | throw <| IO.userError "missing"
      let alt := (rawDepsAlt ci).toList.toArray
      let expected := targetsOf index i.toUInt32 alt
      let lineName := ((tsv[i]!).splitOn "\t")[1]!
      if fromFile != expected || lineName != sanitize (toString names[i]!) then
        bad := bad + 1
        if bad ≤ 5 then IO.eprintln s!"self-check mismatch at node {i} ({names[i]!})"
      checked := checked + 1
    off := off + 4 * deg
  ok := ok && off == bytes.size && bad == 0
  let t3 ← IO.monoMsNow
  let summary := s!"root module: {rootMod}\nlibrary roots: {libs}\nimported modules: {env.header.moduleNames.size}\n" ++
    s!"environment constants: {nConsts}\nproject nodes: {N}\nuser-written nodes: {users}\nedges: {nEdges}\n" ++
    s!"self-check: {checked} nodes compared, {bad} mismatches, file size ok: {off == bytes.size} -> {if ok then "PASS" else "FAIL"}\n" ++
    s!"timings (s): import {(t1 - t0) / 1000}, export {(t2 - t1) / 1000}, self-check {(t3 - t2) / 1000}\n"
  IO.FS.writeFile (outDir / "meta.txt") summary
  IO.print summary
  return if ok then 0 else 1
