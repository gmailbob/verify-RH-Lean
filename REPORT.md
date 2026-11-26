# Verification report

> 中文版: [REPORT.zh-CN.md](REPORT.zh-CN.md)

Status, 2026-11-26: **all steps run, and all pass.**

Target: the readable edition (`grh/`) of <https://github.com/lsernau/grh-lean> at commit
`72fead102f663d5c7a407964a13dc0cf9d977207`. It is a shorter rewriting of Levent Alpöge's Lean
proof. Our earlier verification of that original, 17-million-line library is on the branch
[`original`](https://github.com/gmailbob/verify-RH-Lean/tree/original).

## Conclusion

**Our independent run finds that this Lean library is a complete and valid machine-checked proof
of the Riemann Hypothesis, exactly as Mathlib states it, and of the Generalized Riemann Hypothesis
for Dirichlet L-functions.**

We downloaded the proof from scratch and built it with a hash-verified official Lean release.
Lean's kernel then re-checked every declaration, starting from an empty environment. Finally,
three independently written kernels each accepted an export of our own build. Every check passed,
and the source contains no metaprograms and no way around the kernel.

The four criteria for trusting a Lean proof all hold in our run:

1. **The statement is correct.** `riemannHypothesis` has type `RiemannHypothesis`, Mathlib's own
   definition from `Mathlib.NumberTheory.LSeries.RiemannZeta`. It is not a copy or a restatement.
   Every zero of ζ other than the trivial zeros −2, −4, … has real part 1/2. The four GRH statements
   use only Mathlib's `DirichletCharacter.LFunction` and `IsPrimitive`. All five are syntactically
   identical to the human-reviewed text in `scripts/audit/Reviewed.lean`.
2. **The library compiles.** A fresh clone at the pinned commit, with content matching a pinned
   sha256 digest, builds with the pinned Lean v4.35.0 and Mathlib: 9,852 of 9,852 jobs, 0 errors,
   all 803 project modules. The sources are byte-identical before and after.
3. **The code proves that statement.** The five final theorems have exactly the reviewed statements
   as their types. They depend only on the three standard axioms: `propext`, `Classical.choice` and
   `Quot.sound`. The code has no `sorry`, no new axiom, no `native_decide`, and no `unsafe`,
   `extern` or `implemented_by`. It has no metaprograms at all.
4. **The proof is valid.**
   - **Lean's kernel**, starting from an empty environment (`leanchecker --fresh Main`), accepted
     every declaration the theorems depend on: Lean's core, all of Mathlib and the project.
   - **con-leche**, **con-ron** and **nanoda**, three kernels written independently of Lean's, each
     accepted the export of our own build. nanoda was given an allow-list of the three standard
     axioms and found no other. A self-test first showed that each of them accepts a genuine export
     and rejects a tampered one.

**What this rests on**, as for any Lean proof:
- **The kernels.** Four implementations agree. The three independent ones are binaries shipped in
  the same official Lean release as Lean itself, so they share that one source of binaries.
- **Mathlib's definitions** of ζ and of Dirichlet L-functions.
- **The reading of the ~40-line `Reviewed.lean`.**

This is a verification of the formal proof, not a review of its mathematical ideas. Upstream says
the same of its own checks: "No mathematician has read it through, and no paper comes with it."

**Evidence.** The logs and outputs behind every statement here are in [`evidence/`](evidence/). Its
[README](evidence/README.md) says which file backs which claim.

## Machine

AWS `c8gn.8xlarge`: Graviton4, 32 vCPU aarch64, 61 GiB RAM, no swap, 2.0 TB xfs root on an EBS
volume (network storage), Amazon Linux 2023. `JOBS=28`. Details: `evidence/machine.txt`.

## Results by step

Each step's full log is in `evidence/logs/`; the per-claim files are listed in `evidence/README.md`.

| Step | Result | Notes |
|---|---|---|
| 0 machine | PASS | 2,058 GB available; 61 GiB RAM for 28 build jobs. |
| 1 toolchain | PASS | `lean-4.35.0-linux_aarch64.tar.zst` sha256 `c8f0f8a3…b028` = pin = GitHub asset digest. The binary reports commit `eb6cafb7…`, which is tag `v4.35.0`. |
| 2 source | PASS | A fresh clone is at the pinned commit. `grh/` holds 818 regular files: 803 `.lean` files under `src/`, `Challenge.lean`, `scripts/PrintAxioms.lean` and 13 others. Content digest `ab5bc5e431464ed94f4073ba8b4215481208465d341f702397d81a10b03c25f6`. A second clone, made separately, gives the same digest. Toolchain pin, Mathlib `56a00585…` and all 9 manifest revisions match. |
| 3 scan | PASS | Zero hard-fail tokens in code. No metaprograms, macros or notations. Inventory: see the README section "Reading the scan". |
| 4 deps | PASS | 48 s. All 9 dependency checkouts at the pinned revisions with no modifications; no unexpected packages. Mathlib's cache (9,031 files) is complete: all 8,625 Mathlib modules have an `.olean`. |
| 5 build | **PASS** | `Build completed successfully (9852 jobs)` in 12 min 28 s. 0 errors, 0 failed jobs; all 803 project modules built. 10 warning lines: 9 notes about Mathlib's module system and 1 linter message. |
| 6 self-test | PASS | 8 positive and 10 negative cases, on Lean v4.35.0. |
| 6 statements | PASS | Ran before the build, against Mathlib only. `RiemannHypothesis` is Mathlib's definition (module `Mathlib.NumberTheory.LSeries.RiemannZeta`). All 5 statements are syntactically identical to `Reviewed.lean` and use only Mathlib/core constants (35–40 each). |
| 6 full audit | **PASS** | 3 s. In the built project: the 4 project statements are defined in `Statements`, and all 5 are syntactically identical to `Reviewed.lean`. The 5 theorems are defined in `Main`, have exactly the expected types, and each depends only on `propext`, `Classical.choice` and `Quot.sound`. |
| 7 replay | **PASS** | `leanchecker --fresh --verbose Main` exit 0 after 46 min on one core. Starting from an empty environment, the kernel accepted every declaration `Main` depends on: Lean's core, Mathlib (including the CI-built cache) and all project modules. |
| 8 (pre-build) | PASS | The tree matches the pinned content digest and the step 2 baseline. |
| 8 (post-build) | **PASS** | After the build, the tree still matches the pinned digest and the baseline; the clone is at the pinned commit with no modified files. |
| 9 self-test | PASS | con-leche, con-ron and nanoda each accept a genuine export of a few core theorems and reject a tampered copy. nanoda also refuses an export that uses an axiom outside its allow-list. |
| 9 export | **PASS** | `leanexport Main` with the five theorems as targets: 4,486,595,522 bytes, sha256 `a28b40e7e90aa8477b01294d0afce119d1756d42b582c17a009f85694493396e`. |
| 9 check | **PASS** | All three independent kernels accept the export. con-leche: `accepted 216567 declarations (--verified)`. con-ron: `accepted 216567 declarations (--verified)`. nanoda: `Checked 222117 declarations with no typechecker errors`, with no axiom outside the allow-list. The counts differ because the tools count declarations in different units. |

Two notes on the step 9 log, which holds every run of the step:
- In a first attempt, con-leche and con-ron stopped at once on a command-line option of ours that
  they do not accept (exit 3, a usage error, not a verdict). The self-test now uses the same
  options as the real run, so such a mistake shows up in seconds.
- nanoda prints `1 pretty printer errors: "Unable to print axioms"` next to its verdict. That is
  its pretty-printer, which we do not use; it reports no typechecker error.

## Measurements

Upstream reports a build of one to two hours on 12 cores with 24 GB of memory. On this machine:

| Step | Wall time | Peak memory | Notes |
|---|---|---|---|
| 0–4 and the pre-build stages of 6 and 9 | 76 s from an empty work directory | | downloads included |
| 5 build, 28 jobs | 12 min 28 s | 22.7 GiB in use on the machine; largest process 10.8 GiB RSS | 4.9 core-hours of CPU |
| 6 full audit | 3 s | 8.7 GiB RSS | |
| 7 kernel replay, 1 core | 46 min 0 s | 10.9 GiB RSS | 45.5 min of CPU; ran beside step 9's first run |
| 9 export, 1 core | 3 min 38 s | 12.6 GiB RSS | 4.49 GB written |
| 9 con-leche, 32 threads | 1 min 39 s | 5.1 GiB RSS | |
| 9 con-ron, 32 threads | 1 min 0 s | 7.6 GiB RSS | |
| 9 nanoda, 32 threads | 1 min 39 s | 12.8 GiB RSS | on one thread: 23 min 40 s, 5.6 GiB |

- **Total:** about 70 minutes one step after another. Step 9 can run beside step 7, which brings
  it to about an hour.
- **Disk:** 23 GB in the work directory at the end. The toolchain is 3 GB; Mathlib, the other
  packages and the project's build are 15 GB (the project's own build is 7.5 GB); the export is
  4.5 GB.
- **Memory mappings:** a Lean process that imports the whole project holds 55,794 mappings, and
  the largest count seen during the build was 55,767. The Linux default `vm.max_map_count` is
  65,530, so the default is enough by this measurement. This machine was set to 1,048,576, so we
  did not run at the default itself.
- "Memory in use" excludes the file cache; RSS figures include mapped `.olean` pages, which
  processes share.

## Statement review

`grh/src/Statements.lean` has the same four definitions as the original library's statement
file, and `Main.lean` proves the same five theorem names.

- `Main.riemannHypothesis : RiemannHypothesis`. `Statements.lean` does not define
  `RiemannHypothesis`, so the name resolves to Mathlib's definition. At the pinned
  Mathlib revision that definition reads
  `∀ (s : ℂ) (_ : riemannZeta s = 0) (_ : ¬∃ n : ℕ, s = -2 * (n + 1)) (_ : s ≠ 1), s.re = 1 / 2`.
  This is the standard RH; it excludes only the trivial zeros and the pole.
- The four other statements are short and use only Mathlib notions. They state, for every
  modulus N and Dirichlet character χ: nonvanishing of L(χ, s) for Re s > 1/2 (except the pole
  of the trivial character); zeros in the strip 0 < Re s < 1 lie on Re s = 1/2; the same for
  primitive χ.

## Proof structure (exploration, not verification)

From the declaration-level dependency graph of the built project (`scripts/extra/depgraph/`). We
did not check the mathematics.

- The project has 64,456 declarations, 26,524 of them user-written, and 713,214 dependency edges.
- `riemannHypothesis` needs 49,815 of them (77.3%), including 25,127 of the user-written ones
  (94.7%). The other final theorems need essentially the same set.
- A declaration's **exclusive share** is everything needed *only* through it. These shares do not
  overlap. Shares below are of `riemannHypothesis`'s 49,815 declarations.

| Declaration | Module | Exclusive share |
|---|---|---|
| `New.grh`, the theorem in half-plane form | `New.Reduction.OneSidedBound` | 99.98% |
| `New.eventually_primeRemainder_le_rpow`, the one-sided bound | `New.Reduction.OneSidedBound` | 99.6% |
| `New.star_inequality`, the main inequality | `New.Reduction.MainInequality` | 89.9% |
| `New.Data.integral_forms_long` | `New.Determinant.Twist.LongForms` | 46.5% |
| `New.exists_isRegularFamily` | `New.Congruences.FitTwistsExist` | 32.3% |
| `New.GaloisRep.sphericalCompat_of_odd` | `Lib.GaloisRep.Main.OddRank` | 13.9% |
| `New.Data.exists_err_gaugeLe_compositeLift` | `New.UpperBound.Divisibility.LocalDivisibility` | 3.5% |
| `New.Data.seesaw_identity` | `New.UpperBound.Seesaw.SeesawIdentity` | 2.9% |

Readings, from structure only:
- **Everything runs through one chain.** RH follows from the half-plane theorem `New.grh` through
  `New.zeta_zeros_on_line`, which needs 7 declarations. `New.grh` follows from a one-sided bound,
  and that from the main inequality, which carries 90% of the proof. This matches upstream's
  description of where the main inequality and the half-plane theorem are.
- **Under the main inequality,** the largest single branch is `integral_forms_long` at 46.5%, most
  of it the existence of a regular family of twists (32.3%). Another 29.6% is spread over
  6,847 smaller branches.
- **By area,** the declarations RH needs are spread widely: the largest areas are `New.Spanning`
  (11%), `New.UpperBound` (8%) and `Lib.Weil` (8%).
- 1,397 user-written declarations are not used by `riemannHypothesis`.

The full report is `evidence/proof-structure/depgraph-report.txt`. Exporting and analysing the
graph took 15 s.

## What differs from the run on the original library

- **Source.** A git repository instead of a split archive. Step 2 clones it afresh, checks the
  commit, and checks a sha256 digest over every file, so the content does not rest on git alone.
- **Size.** 803 modules instead of 175,187; a 12-minute build instead of 12 hours; a 46-minute
  kernel replay instead of 13 hours.
- **Metaprograms.** None here. The original used custom tactics that assign proof terms without
  the elaborator's type check, and a command that copies theorems.
- **Independent kernels.** Lean v4.35.0 ships the exporter and three independently written
  checkers. Step 9 uses those binaries on an export of our own build. On the original, our
  machine could not export the 62 GB proof, so we could only check an export published by others.

## What upstream says about its own checks

From `grh/README.md`, with what our run adds:

| Upstream's claim | Our run |
|---|---|
| Every file compiles without errors or `sorry` | reproduced, on a different machine |
| The five theorems depend only on `propext`, `Classical.choice` and `Quot.sound` | reproduced, by our own audit and by nanoda's allow-list |
| An export is accepted by nanoda, con-leche and con-ron | reproduced, on an export of our own build |
| Comparator v4.35.0 accepted the proofs against `Challenge.lean` | not run; our step 6 compares the statements with our own reviewed text instead |
| "No mathematician has read it through, and no paper comes with it" | unchanged: we verified the formal proof only |

Our run also did a fresh kernel replay of the whole environment (step 7).
