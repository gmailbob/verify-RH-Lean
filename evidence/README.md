# Evidence from our run

Supporting files for the claims in [`../REPORT.md`](../REPORT.md), collected from
`$WORKDIR/out` by [`scripts/tools/collect-evidence.sh`](../scripts/tools/collect-evidence.sh).
Text files are copied as produced, except that colour codes are stripped and the machine's
hostname is replaced with `<host>`.

Only small files go here: those that back a claim directly, or that would take a reader many
hours to regenerate. Everything else can be regenerated from the public archive in minutes,
or is third-party material that we link and hash rather than copy (see the end of this file).

| File | Produced by | Backs |
|---|---|---|
| `machine.txt` | collector | the machine every timing refers to |
| `logs/00-check-machine.log` … `logs/09-independent-kernel.log` | each step | every PASS/FAIL line in REPORT's "Results by step". Some logs contain several runs of a step, appended. |
| `logs/extra-depgraph.log` | `scripts/extra/depgraph/run.sh` | the dependency-graph export |
| `scan/scan.txt`, `scan/scan.json` | step 3 | no `sorry`, axioms, `unsafe`, `native_decide` and so on in code; the metaprogram inventory |
| `build/build-summary.txt`, `build/build-monitor.csv` | step 5 | 183,903 jobs, 0 failures; time, disk and memory every 5 min, and the restart at ~06:53 UTC |
| `audit/selftest.txt` | step 6 | the audit checks accept good declarations and reject each kind of cheat |
| `audit/statements.txt` | step 6, before the build | statements identical to `scripts/audit/Reviewed.lean`, using only Mathlib/core |
| `audit/audit.txt` | step 6, after the build | the five theorems' types and axioms (`propext`, `Classical.choice`, `Quot.sound`) |
| `replay/replay.log` | step 7 | `leanchecker --fresh Main`: exit 0, 13 h 15 min, peak RSS |
| `replay/replay-monitor.csv`, `replay/replay-progress.csv` | step 7, `replay_progress.py` | memory and disk over the replay; the progress estimate |
| `independent-kernel/con-leche-solution-mit.log` | step 9 | con-leche: `accepted 1468418 declarations (--verified)` |
| `independent-kernel/solution-mit.ndjson.sha256` | step 9 | the sha256 of the export con-leche checked, equal to MIT's published value |
| `independent-kernel/own-export-memtrend.csv` | step 9, our own export | export size vs memory and swap, minute by minute, until the export was stopped |
| `build-match/project-oleans.sha256.zst` | collector, from our build | sha256 of each of our 175,187 `.olean` files, in the format of MIT's `project-oleans.sha256`. It lets anyone compare our build with theirs, or with their own, without a 12 h build. |
| `build-match/olean-vs-mit.txt`, `build-match/manifest-vs-mit.txt` | `scripts/extra/compare_olean_manifest.py`, and a manifest diff | 76,968 files identical to MIT's; the 98,219 that differ all embed the source path |
| `proof-structure/depgraph-report.txt`, `depgraph-meta.txt` | `scripts/extra/depgraph/run.sh` | the dominator-tree breakdown in REPORT's "Proof structure" |
| `proof-structure/proof-tree.txt` | `scripts/extra/ProofTree.lean` | the top four levels of the proof tree |
| `third-party.sha256` | collector | sha256 and source URL of every third-party file we compared against (MIT's page and logs, the reference site's artifacts, Deicyde's export targets) |

To compare our build with MIT's yourself:

```bash
curl -fsSLO https://math.mit.edu/~drew/grh/project-oleans.sha256
diff <(zstdcat evidence/build-match/project-oleans.sha256.zst) project-oleans.sha256 | grep -c '^>'
#   98219 lines differ; every one is a file that embeds the source path
```

## Not included, and why

| Output | Size | Why it is not here |
|---|---|---|
| Hash lists of the source tree and of the archive members | 7.8–29 MB | regenerated from the public archive by steps 2 and 8 in about 30 s; the digest `859c80e3…` is in REPORT |
| Full build logs (`build.log`) | 8 MB compressed, 176 MB raw | mostly 489,061 warning lines; the summary and monitor back the claims |
| Dependency graph (`nodes.tsv`, `edges.bin`) | 377 MB | `scripts/extra/depgraph/run.sh` regenerates it in about 30 min |
| MIT's export (`solution.ndjson`) | 7.7 GB compressed, 62 GB | MIT's file; its hashes are in `config.sh` and `third-party.sha256` |
| The build itself (`.lake/`) | 1.2 TB | regenerate with step 5 |
| Third-party files (`remark.pdf`, MIT's logs and manifest, reference-site JSON) | ~29 MB | not ours to redistribute; linked and hashed in `third-party.sha256` |
