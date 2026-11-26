# verify-RH-Lean

<p align="center">
  <img src="assets/RH_vs_Claude.jpeg" width="720"
       alt="Illustration: a character at a chalkboard reading 'Riemann Hypothesis: PROVED' and 'RH resolved by Claude'">
</p>
<p align="center"><em>Illustration only. What has actually been verified is in <a href="REPORT.md">REPORT.md</a>.</em></p>

A kit for independently checking the shorter Lean 4 proof of the Riemann hypothesis, as
Mathlib states it, and of GRH for Dirichlet L-functions, published at
<https://github.com/lsernau/grh-lean>. It checks the readable edition, the folder `grh/`:
803 Lean files, about 477,000 lines. That proof is a rewriting of Levent Alpöge's 17-million-line
Lean proof (<https://alpo.ge/remark.pdf>).

This repository holds **no proof and no build output**. It holds scripts that download the
published proof from scratch, verify it against pinned hashes, build it with a verified official
Lean toolchain, and audit the result. Run them yourself and compare. Every check in our own run
passed, and it found a complete and valid machine-checked proof of Mathlib's statement of RH and
of GRH for Dirichlet L-functions. The results are in [REPORT.md](REPORT.md)
([中文](REPORT.zh-CN.md)), and the logs and outputs behind them are in
[`evidence/`](evidence/README.md).

Our earlier verification of the original 17-million-line library, with its report and evidence,
is on the branch [`original`](https://github.com/gmailbob/verify-RH-Lean/tree/original).

## What gets checked

| Step | Script | What it establishes |
|---|---|---|
| 0 | `00-check-machine.sh` | The machine has enough disk, memory, tools and network access. |
| 1 | `01-install-toolchain.sh` | The official Lean v4.35.0 release is installed. Its sha256 matches the pin and the digest GitHub publishes, and the binary reports the commit that tag `v4.35.0` points to. `lean` and `leanchecker` pass smoke tests. |
| 2 | `02-fetch-source.sh` | A fresh clone of the published repository is at the pinned commit. The folder `grh/` holds only regular files, and its content matches a pinned sha256 digest that does not depend on git. File counts, the toolchain pin, the Mathlib pin and every `lake-manifest.json` revision match. The build configuration is a declarative `lakefile.toml`. |
| 3 | `03-scan-source.sh` | No `sorry`, `admit`, `axiom`, `unsafe`, `native_decide`, `implemented_by`, `extern`, `opaque` or `debug.*` options appear in the code; comments are stripped first. Also produces an inventory of every metaprogram, notation and attribute command, all `set_option` keys, the import graph and the full statement files. |
| 4 | `04-fetch-deps.sh` | `lake exe cache get` runs, and every dependency checkout is at its pinned revision with no local changes. Every Mathlib module has a cached `.olean`. |
| 5 | `05-build.sh` | `lake build` of the default targets succeeds: 9,852 jobs, the project's 803 modules on top of Mathlib's cached build. The kernel checks every declaration as it is added. |
| 6 | `06-audit.sh` | A self-test first shows the checks reject `sorry`, custom axioms, `native_decide`, types that are only defeq, statement drift and constants smuggled in through nested proofs. Next, before any build: `Statements.lean` is elaborated against Mathlib alone. `RiemannHypothesis` is confirmed to be Mathlib's own definition, and every statement is syntactically identical to the reviewed text in [`Reviewed.lean`](scripts/audit/Reviewed.lean). After the build: the five final theorems have exactly those types and depend only on `propext`, `Classical.choice` and `Quot.sound`. |
| 7 | `07-kernel-replay.sh` | `leanchecker --fresh Main` re-checks every declaration from an empty environment: Lean core, Mathlib's cached `.olean`s and the whole project. After this step you no longer trust any `.olean` file. |
| 8 | `08-verify-sources-unchanged.sh` | After the build, the project tree still matches the pinned content digest and the step 2 baseline, and the clone is still at the pinned commit. |
| 9 | `09-independent-kernel.sh` | The proof of your own build is exported, and three independently written kernels check the export: **con-leche**, **con-ron** and **nanoda**. nanoda is given an allow-list of the three standard axioms; con-leche and con-ron decline any other axiom. A self-test first shows that each checker accepts a genuine export and rejects a tampered one. The exporter and the checkers are the binaries shipped in the Lean release that step 1 verified. |

Each script prints `PASS` / `WARN` / `FAIL` lines, appends to `$WORKDIR/out/<step>.log`,
and exits non-zero if any check fails. **Do not continue past a failure.**

### What you still have to trust

- **The Lean kernel** in v4.35.0, for steps 5–7, since `leanchecker` uses the same kernel as the
  build. Step 9 removes this for your own build: three separate kernel implementations check
  its export.
- **The Lean release itself.** The exporter and the three checkers come from the same official
  release as Lean. They are separate implementations, but they share that one source of binaries.
- **Mathlib's definitions** of `riemannZeta`, `DirichletCharacter.LFunction` and
  `DirichletCharacter.IsPrimitive`. A statement means only what these definitions mean.
- **Your own reading** of [`Reviewed.lean`](scripts/audit/Reviewed.lean) against the
  mathematics. It is about 40 lines. That is the one step no script can do for you.
- Until step 7 has passed, the Mathlib `.olean` cache that Mathlib's CI built.

## Requirements

Upstream reports a build of one to two hours on 12 cores with 24 GB of memory. The other figures
come from our run on 32 cores; REPORT.md has the full table.

- Linux on x86_64 or aarch64. Other platforms are not supported.
- RAM + swap ≥ 24 GiB. Our 28-job build peaked at 22.7 GiB in use, about 0.8 GiB per job; the
  kernel replay, the export and the checkers each stayed under 13 GiB. `JOBS` defaults to the
  number of cores minus 4, so more cores are used when the machine has them; lower `JOBS` if
  memory is short.
- ≥ 30 GB free disk at `$WORKDIR`; 50 GB recommended. Our run used 23 GB.
- Time on 32 cores: 12 minutes to build, 46 minutes for the single-threaded kernel replay, and
  8 minutes for the export and the three independent checkers. About 70 minutes in all.
- `vm.max_map_count` ≥ 65,530, the Linux default. The largest Lean process in our run held
  55,794 memory mappings, so the default is enough by that measurement, though our machine was
  set higher and we did not run at the default itself. If a build fails with
  `failed to read file '….olean'`, raise it:
  `printf 'vm.max_map_count = 1048576\n' | sudo tee /etc/sysctl.d/99-lean-max-map-count.conf && sudo sysctl --system`
- `bash curl tar zstd sha256sum python3 (≥3.8) git`, GNU `time`, and `tmux` (or another way to
  keep the long steps 5, 7 and 9 running after you log out).
  You do not need elan. The scripts put the pinned toolchain first on `PATH` and pass `--keep-toolchain` to lake.

## Quick start

```bash
git clone https://github.com/gmailbob/verify-RH-Lean && cd verify-RH-Lean
export WORKDIR=/data/grh-verify     # outside the repo; default ~/grh-verify

scripts/00-check-machine.sh
scripts/01-install-toolchain.sh
UPTO=selftest scripts/06-audit.sh           # optional: test the audit checks now (seconds)
UPTO=setup scripts/09-independent-kernel.sh # optional: test the independent checkers now (seconds)
scripts/02-fetch-source.sh
scripts/03-scan-source.sh           # then read $WORKDIR/out/scan.txt, sections B and E
scripts/04-fetch-deps.sh
UPTO=statements scripts/06-audit.sh # statements vs reviewed text, before the build (seconds)
scripts/tools/in-tmux.sh scripts/05-build.sh   # detached; tmux attach -t 05-build
scripts/06-audit.sh
scripts/tools/in-tmux.sh scripts/07-kernel-replay.sh   # single-threaded, 46 min here
scripts/08-verify-sources-unchanged.sh
scripts/tools/in-tmux.sh scripts/09-independent-kernel.sh   # 8 min here
scripts/tools/collect-evidence.sh   # optional: copy the small, claim-backing outputs into evidence/
```

Everything before step 5 took 76 seconds here. A few notes on the long steps:

- Step 5 can be interrupted, even by a reboot, and re-run; Lake keeps finished modules and resumes.
- Step 9 can run beside step 7 if you start it with `FORCE=1 CHECK_JOBS=<cores − 2>`; the replay
  needs only one core.
- To stop a step started with `in-tmux.sh`, press Ctrl-C in its pane: it still writes its summary.
- Do not edit a step script while it runs, because bash reads scripts incrementally.

## Configuration

Every pinned value is in [`config.sh`](config.sh): the source repository, commit and content
digest, file counts, the toolchain version, commit and release hashes, the Mathlib revision, and
machine minimums. More pins live in [`expected/`](expected/): the dependency revisions and the
step 9 export target list. To audit the trust anchors, read `config.sh` and `expected/`.

These environment variables override the defaults:

| Variable | Default | Used by |
|---|---|---|
| `WORKDIR` | `~/grh-verify` | all steps |
| `JOBS` | `nproc − 4` | 5 (`LEAN_NUM_THREADS`) |
| `FORCE=1` | off | 2: delete the clone, with any build in it, and clone again. 9 and the extras: run even while `leanchecker` (step 7) is running |
| `UPTO` | `full` | 6: `selftest`, `statements` (needs step 4) or `full` (needs step 5) |
| `UPTO` | `check` | 9: `setup` (self-test only), `export`, or `check` (all) |
| `REEXPORT=1` | off | 9: redo the export even if `solution.ndjson` exists |
| `CHECK_JOBS` | `nproc` | 9: threads for the three checkers |
| `REPLAY_TARGET` | `Main` | 7 |

## Where things go

```
$WORKDIR/
  src/grh-lean/   fresh clone of the published repository (untrusted)
    grh/          the Lake project; .lake/ appears here after step 4
  toolchain/      lean-4.35.0-linux[_aarch64]/
  out/            <step>.log, scan.txt, scan.json, build.log.zst, build-summary.txt,
                  build-monitor.csv, build-time.txt, audit.txt, replay.log,
                  sources.*.sha256.zst, solution.ndjson, con-leche.log, con-ron.log,
                  nanoda.log, extra/ (optional tools' builds and reports)
```

Nothing is written into the repository, except by `scripts/tools/collect-evidence.sh`. That copies
a run's small, claim-backing outputs into `evidence/`, stripping colour codes and the hostname, so
they can be published next to the report.

## Reading the scan

Step 3 fails only on hard tokens. Section B of `scan.txt` lists everything that steers Lean
beyond plain definitions and proofs. For this proof it is short:

- **No metaprograms at all.** There is no `run_cmd`, `run_tac`, `#eval`, custom `elab`, `macro`,
  `syntax` or notation, and no use of Lean's `Elab` or `Meta` interfaces.
- **204 `attribute` commands** in 143 files: mostly instance declarations and priorities, plus
  `simp`, `fun_prop` and `irreducible` settings. `src/Lib/Speed.lean` holds the global ones. They
  steer elaboration and add no axioms.
- **`set_option`:** `backward.isDefEq.respectTransparency` (33 uses), `synthInstance.maxSize` (5),
  `synthInstance.maxHeartbeats` (5) and `warning.simp.varHead` (1). `lakefile.toml` raises
  `maxHeartbeats` and the stack size for every file. These are elaborator settings; they do not
  affect kernel soundness.
- **Comments only:** the words "admit" and "axiom" occur 19 times, all in English prose inside
  comments.
- All 803 modules are in the import cone of `Main`, and the only outside imports are from Mathlib.
- `grh/Challenge.lean` restates the five theorems with `sorry`, for the Comparator tool. It lies
  outside `src/`, nothing imports it, and the build does not compile it.

## Optional extras

Not part of the verification; in `scripts/extra/`:

- `compare_olean_manifest.py`: compares your compiled `.olean` files with another build's
  manifest of hashes. Files whose source path is embedded are expected to differ.
- `ProofTree.lean`: prints the top of the proof tree under the five final theorems.
- `depgraph/`: where the bulk of the proof lies. `build.sh` builds a compiled exporter of the
  declaration-level dependency graph and a C analyser, compiled with `leanc` if no system
  compiler is present, and tests the analyser against brute force on random graphs. `run.sh`
  computes the dominator tree from each final theorem. A declaration's exclusive share is what
  is needed only through it; these shares do not overlap.

`ProofTree.lean` and `depgraph/` each load the whole build, about 9 GiB of memory.
`depgraph/run.sh` refuses to start while step 7 runs, unless `FORCE=1`.

## Layout

```
config.sh                  all pinned values
expected/                  dependency revisions, export targets
scripts/lib.sh             shared helpers (paths, PASS/FAIL, monitor)
scripts/00..09-*.sh        the steps
scripts/extra/             optional tools (see Optional extras)
scripts/audit/             Reviewed.lean (the text to read), AuditLib.lean, SelfTest.lean, ProofAudit.lean
scripts/tools/             scan_source.py, hash-tree.sh,
                           in-tmux.sh (runs a long step detached, records the exit status),
                           watch-step.sh (waits for a failure, a checkpoint or the end of a step),
                           replay_progress.py (progress estimate for step 7, which prints none),
                           collect-evidence.sh (copies a run's small outputs into evidence/)
REPORT.md                  the results of our run
REPORT.zh-CN.md            Chinese translation of REPORT.md
evidence/                  logs and outputs behind REPORT.md (index: evidence/README.md)
```

Python helpers run with `python3 -I` and only read the downloaded files as data.
No script runs code from the downloaded tree, except Lean and Lake building and loading it: steps 4–7,
the export in step 9, and the extras.
