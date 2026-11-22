# verify-RH-Lean

<p align="center">
  <img src="assets/RH_vs_Claude.jpeg" width="720"
       alt="Illustration: a character at a chalkboard reading 'Riemann Hypothesis: PROVED' and 'RH resolved by Claude'">
</p>
<p align="center"><em>Illustration only. What has actually been verified is in <a href="REPORT.md">REPORT.md</a>.</em></p>

A kit for independently checking the Lean 4 formalization announced in
<https://alpo.ge/remark.pdf>. The announcement claims machine-checked proofs of
the Riemann hypothesis, as Mathlib states it, and of GRH for Dirichlet L-functions.

This repository holds **no proof and no build output**. It holds scripts that
download the published archive, verify it against pinned hashes, build it with a
verified official Lean toolchain, and audit the result. Run them yourself and
compare. Every check in our own run passed, and it found a complete and valid machine-checked proof
of Mathlib's statement of RH; the results are in [REPORT.md](REPORT.md) ([中文](REPORT.zh-CN.md)), and
the logs and outputs behind them are in [`evidence/`](evidence/README.md).

## What gets checked

| Step | Script | What it establishes |
|---|---|---|
| 0 | `00-check-machine.sh` | The machine has enough disk, RAM + swap, tools and network access. |
| 1 | `01-install-toolchain.sh` | The official Lean v4.33.1 release is installed. Its sha256 matches the pin and the digest GitHub publishes, and the binary reports the commit that tag `v4.33.1` points to. `lean` and `leanchecker` pass smoke tests. |
| 2 | `02-fetch-source.sh` | The announcement, all 14 archive parts and the joined archive match pinned sha256 values and sizes. The archive holds only regular files under `lean/`, with no links and no unsafe paths. File counts, the toolchain pin, the mathlib pin and every `lake-manifest.json` revision match. A baseline hash of every file is recorded. |
| 3 | `03-scan-source.sh` | No `sorry`, `admit`, `axiom`, `unsafe`, `native_decide`, `implemented_by`, `extern`, `opaque` or `debug.*` options appear in the code; comments are stripped first. Also produces an inventory of every metaprogram (`run_cmd`, `run_tac`, custom `elab`/`macro`, `addDecl`, direct goal assignment), all `set_option` keys, the import graph and the full statement files. |
| 4 | `04-fetch-deps.sh` | `lake exe cache get` runs, and every dependency checkout is at its pinned revision with no local changes. |
| 5 | `05-build.sh` | `lake build` of all default targets succeeds: 183,903 jobs, covering the project's 175,187 modules plus Mathlib and its dependencies. The kernel checks every declaration as it is added. |
| 6 | `06-audit.sh` | A self-test first shows the checks reject `sorry`, custom axioms, `native_decide`, types that are only defeq, statement drift and constants smuggled in through nested proofs. Next, before any build: `Statements.lean` is elaborated against Mathlib alone. `RiemannHypothesis` is confirmed to be Mathlib's own definition, and every statement is syntactically identical to the reviewed text in [`Reviewed.lean`](scripts/audit/Reviewed.lean). After the build: the five final theorems have exactly those types and depend only on `propext`, `Classical.choice` and `Quot.sound`. |
| 7 | `07-kernel-replay.sh` | `leanchecker --fresh Main` re-checks every declaration from an empty environment: Lean core, mathlib's cached `.olean`s and the whole project. After this step you no longer trust any `.olean` file. |
| 8 | `08-verify-sources-unchanged.sh` | After the build, the project tree is byte-identical to the archive contents, and to the step 2 baseline. |
| 9 | `09-independent-kernel.sh` | Optional, recommended. Exports the proof with `lean4export` and checks it with **con-leche**, an independently written kernel, using the same tools, revisions and export targets as MIT's run. It compares the export's hash with MIT's. A self-test first shows con-leche accepts a genuine export and rejects a tampered one. With `EXPORT_SOURCE=mit` it checks MIT's published export instead, after verifying both of MIT's published hashes. That needs less memory, but it does not tie the export to your own build. See "Step 9 resources" below. |

Each script prints `PASS` / `WARN` / `FAIL` lines, appends to `$WORKDIR/out/<step>.log`,
and exits non-zero if any check fails. **Do not continue past a failure.**

### What you still have to trust

- **The Lean kernel** in v4.33.1, for steps 5–7, since `leanchecker` uses the same kernel as the
  build. Step 9 has [con-leche](https://github.com/leanprover/con-leche), an independently written
  kernel, check an export of the proof:
  - Run on **your own export** (the default), it removes this trust.
  - Run on **MIT's published export** (`EXPORT_SOURCE=mit`), it covers MIT's file. That file is linked
    to your build only through the `.olean` comparison, and you rely on MIT for how the export was made.
- **Mathlib's definitions** of `riemannZeta`, `DirichletCharacter.LFunction` and
  `DirichletCharacter.IsPrimitive`. A statement means only what these definitions mean.
- **Your own reading** of [`Reviewed.lean`](scripts/audit/Reviewed.lean) against the
  mathematics. It is about 40 lines. That is the one step no script can do for you.
- Until step 7 has passed, the mathlib `.olean` cache that mathlib's CI built.

## Requirements

- Linux on x86_64 or aarch64. Other platforms are not supported.
- 32+ cores recommended. At 28 parallel jobs on 32 Graviton4 cores the build took 12 h; the
  reference run took 7 h on 128 vCPU. The step 7 replay is single-threaded and took 13 h.
- RAM + swap ≥ 96 GiB. With 64 GiB RAM, add swap:
  `sudo fallocate -l 64G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`
  and add `/swapfile none swap defaults,nofail 0 0` to `/etc/fstab` so a reboot during the build keeps it.
- `vm.max_map_count` ≥ 1,048,576. That is Ubuntu's default, but Amazon Linux and RHEL default
  to 65,530. Deep modules here import over 20,000 `.olean` files. With the low limit, Lean runs
  out of memory mappings and reports `failed to read file '….olean'`. To fix it persistently:
  `printf 'vm.max_map_count = 1048576\n' | sudo tee /etc/sysctl.d/99-lean-max-map-count.conf && sudo sysctl --system`
- ≥ 1.5 TB free disk at `$WORKDIR`; 2 TB recommended. The build outputs alone are ~1.2 TB, and
  step 9 adds ~70 GB for an export.
- `bash curl tar gzip zstd sha256sum python3 (≥3.8) git`, GNU `time`, and `tmux` (or another
  way to keep the long steps 5, 7 and 9 running after you log out).
  You do not need elan. The scripts put the pinned toolchain first on `PATH` and pass `--keep-toolchain` to lake.

## Quick start

```bash
git clone https://github.com/gmailbob/verify-RH-Lean && cd verify-RH-Lean
export WORKDIR=/data/rh-verify      # outside the repo; default ~/rh-verify

scripts/00-check-machine.sh
scripts/01-install-toolchain.sh
UPTO=selftest scripts/06-audit.sh   # optional: test the audit checks now (seconds)
scripts/02-fetch-source.sh
scripts/03-scan-source.sh           # then read $WORKDIR/out/scan.txt, sections B and E
scripts/04-fetch-deps.sh
UPTO=statements scripts/06-audit.sh # statements vs reviewed text, before the build (a minute)
scripts/tools/in-tmux.sh scripts/05-build.sh   # detached; tmux attach -t 05-build
scripts/06-audit.sh
scripts/tools/in-tmux.sh scripts/07-kernel-replay.sh   # single-threaded: ~13 h on Graviton4
scripts/08-verify-sources-unchanged.sh
scripts/tools/in-tmux.sh scripts/09-independent-kernel.sh   # optional, after step 7; see "Step 9 resources"
scripts/tools/collect-evidence.sh   # optional: copy the small, claim-backing outputs into evidence/
```

Steps 0–4 and the first two stages of step 6 take about ten minutes in total.
Step 5 can be interrupted, even by a reboot, and re-run; Lake keeps finished modules and
resumes. To stop a step started with `in-tmux.sh`, press Ctrl-C in its pane: it still writes its
summary. Do not edit a step script while it runs, because bash reads scripts incrementally.

### Step 9 resources

| Stage | Measured here (32 cores, 61 GiB RAM + 64 GiB swap, EBS disk) | Advice |
|---|---|---|
| Setup and self-test | 3 min | none |
| Export of your build (default) | ~14 MB/s for the first ~20 GB, then under 1 MB/s. Stopped at 25 of ~62 GB with ~13 h still to go | Needs room for the whole project plus the exporter's tables (>30 GB): **≥128 GB RAM**, ideally local NVMe rather than network storage. Expected ~1–2 h then (not measured). With less RAM, every `.olean` page that falls out of the cache is re-read from disk, ~1 ms per read on network storage. More swap does not help. |
| `EXPORT_SOURCE=mit` download | 7.7 GB at ~6 MB/s from MIT's server, ~20 min; unpacking to 61.6 GB takes a few minutes | ~70 GB of disk |
| con-leche | 12 min 44 s: 8 min parsing the 61.6 GB file from EBS, then 4.8 min checking on 32 cores. Peak RSS 43.6 GiB | ~50 GB RAM; uses all cores. Parsing is faster when the file is in RAM or on local NVMe. |

## Configuration

Every pinned value is in [`config.sh`](config.sh): URLs, sha256s, sizes, file counts,
toolchain version and commit, the mathlib revision, machine minimums, and the step 9 tool
revisions. More pins live in [`expected/`](expected/): the per-part hashes, the dependency
revisions, and the step 9 export target list. To audit the trust anchors, read `config.sh` and
`expected/`.

These environment variables override the defaults:

| Variable | Default | Used by |
|---|---|---|
| `WORKDIR` | `~/rh-verify` | all steps |
| `JOBS` | `nproc − 4` | 5 (`LEAN_NUM_THREADS`) |
| `FORCE=1` | off | 2: re-extract over an existing tree. 9 and the extras: run even while `leanchecker` (step 7) is running |
| `UPTO` | `full` | 6: `selftest`, `statements` (needs step 4) or `full` (needs step 5) |
| `UPTO` | `check` | 9: `setup` (tools and self-test only), `export`, or `check` (all) |
| `EXPORT_SOURCE` | `build` | 9: `build` exports your build; `mit` checks MIT's published export instead |
| `REEXPORT=1` | off | 9: redo the export even if `solution.ndjson` exists |
| `SETUP_JOBS` | `4` | 9: parallel jobs when building `lean4export` and con-leche |
| `REPLAY_TARGET` | `Main` | 7 |

## Where things go

```
$WORKDIR/
  download/    remark.pdf, lean.tar.gz.part01..14, lean.tar.gz     (untrusted)
  src/lean/    extracted project; .lake/ appears here after step 4 (untrusted)
  toolchain/   lean-4.33.1-linux[_aarch64]/, and lean-4.36.0-… for step 9
  extra-tools/ lean4export and con-leche checkouts and builds (step 9)
  out/         <step>.log, scan.txt, scan.json, build.log.zst, build-summary.txt,
               build-monitor.csv, audit.txt, replay.log, sources.*.sha256.zst,
               solution*.ndjson and con-leche-*.log (step 9, ~62 GB each export),
               project-oleans.sha256.zst (hash of every compiled file, for evidence/),
               extra/ (optional tools' builds and reports),
               reference/ (third-party files you fetched by hand for cross-checks, if any)
```

Nothing is written into the repository, except by `scripts/tools/collect-evidence.sh`. That copies
a run's small, claim-backing outputs into `evidence/`, stripping colour codes and the hostname, so
they can be published next to the report.

## Reading the scan

Step 3 fails only on hard tokens. Section B of `scan.txt` lists metaprograms that
need a human to read them. For this archive, section B contains:

- **5 × `run_cmd`** in `BuildAid/D1–D5`. Each adds a namespace name to Lean's
  library-suggestion deny list. They contribute nothing to any proof.
- **`kexactB`** (277 uses), **`kcopy`** (5 uses) and **one `run_tac` block**
  (`Development/AbelianVarietyTheory/Proofs/IwasawaDecomposition/ExistsGIs.lean`) assign
  a term to the goal *without the elaborator's type check*. The other 31 `run_tac` uses
  only revert hypotheses, or build a type-checked `Subsingleton.elim` proof. Only the kernel checks
  these proofs. That is enough for soundness: the kernel checks every declaration
  during the build and again in step 7, and a mistyped term makes the build fail.
  It does mean these places depend entirely on the kernel.
- **`cpt_copy_thms`** (`Formalism/HermitianCurvature/HermitianCurvatureProofs/CutCptCopy.lean`)
  copies a dependency cone of definitions and theorems, substituting constants, through
  `addDecl`. Each copy goes through the kernel. The command can only create definitions
  and theorems, not axioms.
- `allowUnsafeReducibility` (37 uses) and `maxHeartbeats 0` (4 uses) are elaborator
  settings. They do not affect kernel soundness.
- All 175,187 project modules are in the import cone of `Main`.

## About the reference run

A third party published a run at <https://proveriemannhypothesis.github.io/>. Treat
everything there as claims to cross-check, not as inputs: these scripts never read from it.

What agrees with the pins here: the part and archive hashes, `lean-toolchain`,
`lake-manifest.json`, the toolchain hash (their x86_64 asset), the uncompressed archive size,
and the 183,903 build jobs. That run checked the theorem types and axioms but did not do the
kernel replay in step 7 (`result.json`: "Omitted at user request; no successful
fresh-kernel replay is claimed").

## Optional extras

Not part of the verification; in `scripts/extra/`:

- `compare_olean_manifest.py`: compares your compiled `.olean` files with another build's
  manifest of hashes, such as MIT's `project-oleans.sha256`. Files whose source path is embedded
  are expected to differ.
- `ProofTree.lean`: prints the top of the proof tree under the five final theorems.
- `depgraph/`: where the bulk of the proof lies. `build.sh` builds a compiled exporter of the
  declaration-level dependency graph and a C analyser, compiled with `leanc` if no system
  compiler is present, and tests the analyser against brute force on random graphs. `run.sh`
  computes the dominator tree from each final theorem. A declaration's exclusive share is what
  is needed only through it; these shares do not overlap. It took 28 min here: import, then an
  export bound by the EBS disk, then a self-check. Peak memory was ~55 GB, mostly cache.

Each loads or reads the whole build, so avoid running them during step 7: they compete with the
replay for the file cache.

## Layout

```
config.sh                  all pinned values
expected/                  per-part hashes, dependency revisions, export targets
scripts/lib.sh             shared helpers (paths, PASS/FAIL, monitor)
scripts/00..09-*.sh        the steps
scripts/extra/             optional tools (see Optional extras)
scripts/audit/             Reviewed.lean (the text to read), AuditLib.lean, SelfTest.lean, ProofAudit.lean
scripts/tools/             check_tar.py, scan_source.py, tar_hashes.py, hash-tree.sh,
                           in-tmux.sh (runs a long step detached, records the exit status),
                           watch-step.sh (waits for a failure, a checkpoint or the end of a step),
                           replay_progress.py (progress estimate for step 7, which prints none),
                           collect-evidence.sh (copies a run's small outputs into evidence/)
REPORT.md                  results of our run
REPORT.zh-CN.md            Chinese translation of REPORT.md
evidence/                  logs and outputs behind REPORT.md (index: evidence/README.md)
```

Python helpers run with `python3 -I` and only read the downloaded files as data.
No script runs code from the downloaded tree, except Lean and Lake building and loading it: steps 4–7,
the export in step 9, and the extras. Step 9 also clones and builds `lean4export` and con-leche from
GitHub, at pinned commits.
