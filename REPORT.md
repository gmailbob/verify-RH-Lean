# Verification report

> 中文版: [REPORT.zh-CN.md](REPORT.zh-CN.md)

Status, 2026-11-22: **all steps run. Steps 0–8 pass. Step 9 passes on MIT's published export.**

## Conclusion

**Our independent run finds that the Lean library published at <https://alpo.ge/remark.pdf> is a
complete and valid machine-checked proof of the Riemann Hypothesis, exactly as Mathlib states it,
and of the Generalized Riemann Hypothesis for Dirichlet L-functions.**

We rebuilt the library from scratch on different hardware from the reference run (aarch64 rather
than x86_64). We re-checked every declaration with Lean's kernel, starting from an empty
environment. That is a step the reference run skipped. We then had a second, independently written
kernel accept the exported proof. Every check passed, and nothing in the source or its
metaprograms gives a way around the kernel. This agrees with the
[joint statement of the Lean and Mathlib communities](https://leanprover-community.github.io/blog/posts/riemann-hypothesis/)
and with the checks published at <https://math.mit.edu/~drew/grh/>.

The four criteria for trusting a Lean proof all hold in our run:

1. **The statement is correct.** `riemannHypothesis` has type `RiemannHypothesis`, Mathlib's own
   definition from `Mathlib.NumberTheory.LSeries.RiemannZeta`. It is not a copy or a restatement.
   Every zero of ζ other than the trivial zeros −2, −4, … has real part 1/2. The four GRH statements
   use only Mathlib's `DirichletCharacter.LFunction` and `IsPrimitive`. All five are syntactically
   identical to the human-reviewed text in `scripts/audit/Reviewed.lean`.
2. **The library compiles.** It builds from the hash-verified archive with the pinned Lean v4.33.1
   and Mathlib: 183,903 of 183,903 jobs, 0 errors. The sources are byte-identical before and after.
   76,968 of our compiled files, `Main.olean` included, are byte-identical to MIT's independent
   build. The other 98,219 are exactly the files in which Lean embeds the absolute source path.
3. **The code proves that statement.** The five final theorems have exactly the reviewed statements
   as their types. They depend only on the three standard axioms: `propext`, `Classical.choice` and
   `Quot.sound`. There is no `sorry`, no new axiom, no `native_decide`, and no `unsafe`, `extern` or
   `implemented_by` code. The project's metaprograms contain no file or process I/O calls.
4. **The proof is valid.**
   - **Lean's kernel**, starting from an empty environment (`leanchecker --fresh Main`, 13 h),
     accepted every declaration the theorems depend on. That covers Lean core, all of Mathlib and
     all 175,187 project modules.
   - **con-leche**, a kernel written independently of Lean's, accepted all 1,468,418 declarations
     of the exported proof. A self-test first showed it accepts a genuine export and rejects a
     tampered one.

**What this rests on**, as for any Lean proof:
- **The kernels.** Two independent implementations agree.
- **Mathlib's definitions** of ζ and of Dirichlet L-functions. They went through Mathlib's review,
  and the community statement notes that the RH statement in particular has been vetted by experts
  in Lean and number theory.
- **The reading of the ~40-line `Reviewed.lean`.**

One link we did not close ourselves: the export that con-leche checked is MIT's published file,
verified against both of its published hashes, not an export of our own build. Our build reaches
that file through the file-for-file `.olean` match. The community statement reports that many
independent builds reproduce the same export file. Exporting our own build needed more RAM than
this machine has; see the step 9 section.

This is a verification of the formal proof, not a review of its mathematical ideas. A first map of
where those ideas sit is in "Proof structure" below.

**Evidence.** The logs and outputs behind every statement here are in [`evidence/`](evidence/). Its
[README](evidence/README.md) says which file backs which claim.

## Machine

AWS `c8gn.8xlarge`: Graviton4, 32 vCPU aarch64, 61 GiB RAM + 64 GiB swap, 2.0 TB xfs root on an
EBS volume (network storage), Amazon Linux 2023. `JOBS=28`. Details: `evidence/machine.txt`.

## Results by step

Each step's full log is in `evidence/logs/`; the per-claim files are listed in `evidence/README.md`.

| Step | Result | Notes |
|---|---|---|
| 0 machine | PASS | 1,993 GB available. |
| 1 toolchain | PASS | `lean-4.33.1-linux_aarch64.tar.zst` sha256 `f7353a8b…5f07` = pin = GitHub asset digest; binary reports commit `819816b2…`, which is tag `v4.33.1`. `leanchecker --fresh Init` replays in 47 s using 0.5 GB. |
| 2 source | PASS | `remark.pdf`, all 14 parts and `lean.tar.gz` (`9631b4f0…c7fc`, 239,275,554 bytes) match. The archive contains 175,190 regular files under `lean/` (175,187 `.lean`) and no links or unsafe paths. Toolchain pin, mathlib `0df444a3…` and all 9 manifest revisions match. Digest of the baseline hash list: `859c80e3fe4912ad9e18ad359edbfdc62fb845ad340add30b5caa0fdc74d2ee1`. |
| 3 scan | PASS | Zero hard-fail tokens in code or comments. Metaprogramming inventory: see the README section "Reading the scan". |
| 4 deps | PASS | 1.5 min. All 9 dependency checkouts at the pinned revisions with no modifications; no unexpected packages. Mathlib's cache (8,690 files from `lakecache.blob.core.windows.net`) is complete: all 8,312 Mathlib modules have an `.olean`. Mathlib's toolchain file is v4.33.1; the other dependencies declare v4.33.0 but are built with v4.33.1. `.lake` is 7.6 GB. |
| 5 build | **PASS** | `Build completed successfully (183903 jobs)`, the same job count as the reference run. 0 errors, 0 failed jobs; all 175,187 project modules built, ending with `Supplements.Kernels.MainTheoremsAll` then `Main`. Time: 05:07:52–06:53:34 and 07:04:51–17:23:22 UTC, so 12 h 04 m of build time. In between, it was restarted once after raising `vm.max_map_count` (see the README requirements), and Lake kept the 27,864 modules already built. 104,045 jobs reported warnings (489,061 `warning:` lines); the reference reports 460,321 warnings in an unstated unit. `.lake` is 1.2 TB; 709 GB of disk free after. Peak memory 31 GB in use; swap never used. |
| 6 self-test | PASS | 8 positive and 10 negative cases. |
| 6 statements | PASS | Ran before the build, against Mathlib only, in 3 s using 7.5 GB. `RiemannHypothesis` is Mathlib's definition (module `Mathlib.NumberTheory.LSeries.RiemannZeta`). All 5 statements are syntactically identical to `Reviewed.lean` and use only Mathlib/core constants (35–40 each). |
| 6 full audit | **PASS** | 49 s, 35 GB peak memory. In the built project: `RiemannHypothesis` is defined in `Mathlib.NumberTheory.LSeries.RiemannZeta`; the 4 project statements are defined in `Statements`; all 5 are syntactically identical to `Reviewed.lean` and use only Mathlib/core constants. The 5 theorems are defined in `Main`, have exactly the expected types, and each depends only on `propext`, `Classical.choice` and `Quot.sound`. |
| 7 replay | **PASS** | `leanchecker --fresh --verbose Main` exit 0. Starting from an empty environment, the kernel accepted every declaration `Main` depends on: Lean core, Mathlib (including the CI-built cache) and all project modules. 17:27:45 → 06:42:29 UTC: 13 h 14 m 44 s wall clock, 45,696 s CPU on one core. Peak RSS 48.5 GB, mostly file-backed `.olean` pages; peak anonymous memory ~16 GB; swap never used. The reference run skipped this step. |
| 8 (pre-build) | PASS | The extracted tree is byte-identical to the archive members. |
| 8 (post-build) | **PASS** | After the build, all 175,190 files are byte-identical to the archive members and to the step 2 baseline (hash-list digest `859c80e3…`). |
| 9 independent kernel | **PASS on MIT's export**; own export not done | Setup and self-test PASS. con-leche, an independently written kernel, accepts all 1,468,418 declarations of MIT's published export of `Main` (both published hashes verified). **Our own export was not completed**, so no hash comparison was made; see the step 9 section for what this does and does not show. |

## Statement review

- `Main.riemannHypothesis : RiemannHypothesis`. `Statements.lean` does not define
  `RiemannHypothesis`, so the name resolves to Mathlib's definition. At the pinned
  mathlib revision that definition reads
  `∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2`.
  This is the standard RH; it excludes only the trivial zeros and the pole.
- The four other statements in `Statements.lean` are short and use only Mathlib
  notions. They state, for every modulus N and Dirichlet character χ: nonvanishing of
  L(χ, s) for Re s > 1/2 (except the pole of the trivial character); zeros in the
  strip 0 < Re s < 1 lie on Re s = 1/2; the same for primitive χ.

## Step 9, the independent kernel: what was done, what it shows, what it does not

**Setup and self-test.**
- Lean v4.36.0 was hash-checked.
- `lean4export` was built at `15f6055e` (tag v4.33.0) and con-leche at `cd2eceab` (master), the same
  revisions as MIT's run.
- con-leche accepted a genuine export of a few `Init` theorems. It rejected a tampered copy, in which
  one theorem's proof was swapped for another's, with `type mismatch in theorem Nat.add_comm`.

**Our own export: attempted, not completed.**
- `lean4export Main` with the pinned export targets ran from 06:45 to 07:52 UTC on 2026-11-22. For
  about the first 20 GB it wrote around 14 MB/s.
- At 25.4 GB of the expected ~61.6 GB (41%) it ran out of memory headroom:
  - The exporter's own tables had reached ~32 GB.
  - It reads ~90 GB of `.olean` data in random order.
  - That did not fit in 61 GiB of RAM, so `.olean` pages were evicted and re-read from the EBS disk.
- A 30 s sample showed 26,045 major page faults and 819 MiB read from disk. The process used only
  1 s of CPU and wrote 23 MiB of export.
- Swap was not the bottleneck: it stayed at ~3.8 GB.
- At under 1 MB/s, about 13 more hours were projected. The minute-by-minute record is in
  `evidence/independent-kernel/own-export-memtrend.csv`. Raising disk readahead did not help. We
  stopped it and decided not to complete it, to save time.
- **So we have no export of our own build, and no comparison of its hash with MIT's.**

**con-leche on MIT's published export (`EXPORT_SOURCE=mit`).**
- Downloaded from <https://math.mit.edu/~drew/grh/>. The file matches both hashes MIT publishes:
  - compressed `61a8938a…`, 7,699,933,588 bytes: **matched**;
  - unpacked `5ea74b91…`, 61,570,595,788 bytes: **matched**.
- con-leche verdict: **`accepted 1468418 declarations (--verified)`**, exit 0. That is the same
  declaration count as MIT's run. Time: 12 min 44 s (475 s parsing the 61.6 GB file from EBS, 286 s
  checking on 32 workers). Peak RSS 43.6 GiB, no swap. Log:
  `evidence/independent-kernel/con-leche-solution-mit.log`.

**What this shows:**
- An independently written kernel, run by us on our machine, accepts the file MIT published as their
  export of `Main`. This no longer rests on MIT's logs.
- Our build matches MIT's build. 76,968 `.olean` files are byte-identical, including `Main.olean`.
  The 98,219 that differ are exactly the ones that carry a source path (see "Independent kernel
  checks by others" below).

**What this does not show:**
- **That the export file came from our build.** We rely on MIT for how the export was produced:
  their build and their `lean4export` run, which by their own caveats were on unsandboxed machines.
  The published hashes only prove we checked the file they published.
- That the 98,219 path-carrying `.olean` files equal MIT's apart from the path. That is inferred from
  the counts and from MIT's explanation, not compared byte by byte.
- So for our own build, only Lean's kernel has checked the proof (steps 5–7). The independent-kernel
  verdict reaches our build through the `.olean` comparison, not directly.

**To close the gap,** run step 9 in its default mode, which exports your own build, on a machine
that fits it: ≥128 GB RAM, ideally on local NVMe storage rather than network storage. The export is
then expected to take about 1–2 h, an estimate we did not measure. If its sha256 equals
`5ea74b91…`, the independent-kernel verdict applies to your build byte for byte. If it differs,
con-leche checks your export directly.

## Proof structure (exploration, not verification)

Read from the formal statements and how they are wired (`scripts/extra/ProofTree.lean`, then the
source files). We did not check the mathematics.

- **Top layer, classical.** RH and the critical-strip forms follow from `UpperTheory.EveryCharacter`,
  which says L(χ, s) ≠ 0 for Re s > 1/2 for every Dirichlet character χ. That is word for word the
  final statement `DirichletLNonvanishingRightOfHalf`. The reductions (`Formalism.VW.rh_of_right`,
  `Claim.strip`, `Claim.prim_zero`, `Claim.prim_reflect`, `Formalism.VW.critLine`) are standard:
  the functional equation, reduction to primitive characters, and non-vanishing of Euler and gamma
  factors. Each has 0–4 project dependencies.
- **Everything else feeds `EveryCharacter`**, through
  `UpperTheory.LiteratureTheorems.every_character_of_literature_of_vWin`. Its inputs:
  - **Results the project labels as literature:**
    - `UpperTheory.GalStar.Row0b`: Galois representations attached to regular algebraic, polarized
      cuspidal automorphic representations of GL_a over CM fields, with local-global
      compatibility.
    - Local Langlands for GL_n.
    - Resolution of singularities in characteristic 0.
    - Theta-integral matching and "self-intersection volume estimates".
  - **`UpperTheory.Top.VWin`:** an explicit estimate for every primitive character ψ on windows
    [Y, Y²] (constant 401), proved via `automorphic_window_of_inputs` ("modularity argument",
    "threshold arguments") and base change.
- **Where the new mathematics must sit:** in that combination. The dominator analysis below shows
  which part carries most of the proof.
- **The "literature" results are proved inside the project, not assumed.** The five theorems use no
  axioms beyond the standard three. So correctness does not depend on whether these internal
  statements match the published theorems they are named after; only on the kernel and on Mathlib's
  definitions.

### Where the bulk of the proof lies (dominator analysis)

Method: `scripts/extra/depgraph/`. It exports the declaration-level dependency graph of the built
project: 1,905,921 project declarations, of which 1,079,944 are user-written, and 20,986,047 edges.
The environment had 186,200 modules and 2,701,132 constants, the same totals as MIT's audit log.
From the root, it computes the dominator tree. A declaration's **exclusive share** is everything
needed *only* through it. Unlike cone sizes, these shares do not overlap. Shares below are of
`riemannHypothesis`'s cone: 1,265,256 declarations, 791,182 of them user-written. The other final
theorems have essentially the same cone.

| Declaration | Cone | Exclusive share |
|---|---|---|
| `UpperTheory.FinalTheorems.everyCharacter` (the half-plane theorem) | 100% | 100%. The RH and strip forms above it add only a handful of declarations. |
| `UpperTheory.LiteratureTheorems.every_character_of_literature_of_vWin` (the combining theorem) | 83.7% | 66.5% |
| `UpperTheory.Lit.every_character_of_theta_integrals_local_matching` | 61.0% | **42.7%**, the largest single part |
| `UpperTheory.Lit.nonempty_hyps_definite_side_of_closed_bound`, within it | | 35.5% |
| `SelfIntersectionVolumeEstimates.topCovolSlim2_use_alt_alt`, via Moriwaki bigness / Hilbert–Samuel / tower volume | | 6.3% |
| `UpperTheory.One.vwin_of_row` (the `VWin` window estimate) | 21.9% | 7.2% |
| `UpperTheory.Gal.Int.galoisLocalGlobalStrong_recParameter` (`Row0b`, Galois representations via a theta lift and a geometric realization) | 24.0% | 7.1% |
| `UpperTheory.Zero.LLC.recTExists` (local Langlands input) | 1.7% | 0.05% |
| `Formalism.VW.rh_of_every` (RH from the half-plane theorem) | 6 declarations | none |
| `Claim.strip`, `Claim.zeta` (critical-strip forms) | 8 and 10 declarations | none |

Readings, from structure only:
- **The classical reductions are tiny.** Deriving RH and the critical-strip statements from the
  half-plane theorem takes about a dozen declarations.
- **The theta-integral / local-matching argument dominates.** It holds 42.7% exclusively, most of it
  under the hypotheses established for its "definite side". That is where a reader should look first.
- **`VWin` and the Galois-representation input are each about 7%.** The self-intersection / volume
  estimate is about 6%.
- **About a third of the project, 640,665 declarations (288,762 user-written), is not used by any of
  the five final theorems.** It is still compiled and kernel-checked.

Run time: 28 min. That was 5.7 min to import the project from a cold cache, 16 min to export (bound
by the EBS disk) and 6.5 min for the self-check. The analysis itself takes seconds. Peak RSS was
54.7 GB, mostly cached `.olean` pages. The full report is `evidence/proof-structure/depgraph-report.txt`.

## Independent kernel checks by others, and how our build relates to them

Andrew Sutherland (MIT) publishes further checks of the same archive at
<https://math.mit.edu/~drew/grh/> (page updated 2026-11-21 12:55 UTC). We reviewed the page
and its logs; these are their claims, not our runs:

- Two independently written kernels accept the full exported proof (`lean4export` of `Main`,
  61,570,595,788 bytes, sha256 `5ea74b91…`): **nanoda** (Rust; exit 0, 27 min 42 s on 80 threads,
  89 GB peak) and **con-leche** master `cd2eceab` (1,468,418 declarations accepted in
  `--verified` mode; 3 min 15 s on 64 threads, 47.8 GB peak). Both logs end with exit status 0.
- `con-leche --compare` matches all five theorems against a challenge file that imports only
  Mathlib, so the statements checked are Mathlib's.
- `leanchecker` per module, 175,187 of 175,187 pass. `lean4lean` per module, 175,187 pass; five
  needed a raised step limit for `decide +kernel` computations.
- Their environment has 15 axioms, all in `Init`. The five theorems use only `propext`,
  `Classical.choice` and `Quot.sound`.
- At that time the Lean default and paranoid kernels on the export, and the end-to-end
  `lake comparator` run, were still in progress.
- Caveats on their own page: they compiled each file by calling `lean` directly, not through
  `lake build`, on unsandboxed cloud machines.

**Our build matches MIT's build, apart from embedded paths.** Our `Main.olean`, built on aarch64
through `lake build`, has sha256 `9146dfb4…`, identical to theirs. Their page does not state their
architecture. Against their manifest of all 175,187 `.olean` hashes, 76,968 of our files are byte-identical and 98,219 differ. Every difference
contains our source path and no identical file does. Lean v4.33 stores the absolute source path
next to saved linter messages; their page reports exactly 76,968 path-free and 98,219
path-containing files. So, apart from embedded paths, our independent `lake build` reproduces the
build whose export the independent kernels accepted. For the path-carrying files this is inferred
from the counts and from MIT's explanation, not compared byte by byte.
(`scripts/extra/compare_olean_manifest.py`; 7.5 min at idle priority.) Our full `.olean` hash
list is in `evidence/build-match/project-oleans.sha256.zst`, in MIT's format, so anyone can redo
this comparison, or compare with their own build, without building.

## Observations about the reference run's claims

Source: <https://proveriemannhypothesis.github.io/>.

- Its part hashes, archive hash, `lean-toolchain` and `lake-manifest.json` agree with ours.
- Disk: its 16:15 UTC telemetry sample shows a 1.08 TB root disk, while its summary says
  1.17 TiB used on a 2 TiB disk. Its `archive/storage-at-migration.json` explains this: at
  07:28 UTC on Nov 21 the run's data was on a 2 TiB disk with 1.28 TB used, so it moved to a
  bigger disk after the build. Our 1.2 TB `.lake` agrees with that.
- Its `result.json` agrees with ours: 183,903 / 183,903 build jobs and 0 failures.
  Axioms: `Classical.choice`, `Quot.sound` and `propext` only. 175,187 source files unchanged.
  Toolchain sha256 `890afd18…`, which is the official x86_64 asset (pinned in `config.sh`).
  Kernel replay: "skipped … Omitted at user request".
- Its `memory-peak.json` reports a "build memory peak" of 210.0 GiB (225,485,783,040 bytes).
  That equals the cgroup limit, includes the file cache, and comes from a single sample
  (first = peak = last = 16:34:44 UTC), so it says nothing about how much memory Lean needs.
  The only useful figure is the 16:15 UTC `machine-sample.json` snapshot: 36.0 GiB used of
  243.8 GiB at 48 threads, about 40 minutes into the build. That is a snapshot, not a peak.
  Both match what the reference site shows.
