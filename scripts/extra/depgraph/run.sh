#!/usr/bin/env bash
# Optional exploration: export the project's declaration-level dependency graph and report
# where the bulk of the proof lies (dominator tree from each final theorem).
# Loads the whole built project once (~35 GB peak, a few minutes). Do not run it during
# step 7: it competes with the replay for the file cache. It refuses while leanchecker runs.
# Outputs: $OUT/extra/depgraph/{nodes.tsv,edges.bin,meta.txt}, $OUT/extra/depgraph-report.txt
source "$(dirname "$0")/../../lib.sh"
need_toolchain
need_project
need_max_map_count
log_to extra-depgraph.log

[[ -d "$PROJ/.lake/build/lib" ]] || die "project not built; run scripts/05-build.sh"
if pgrep -x leanchecker >/dev/null && [[ "${FORCE:-0}" != 1 ]]; then
  die "leanchecker (step 7) is running; this would slow it down. Wait, or set FORCE=1."
fi
B="$OUT/extra/depgraph-build"
[[ -x "$B/.lake/build/bin/depgraph" && -x "$B/depgraph_analyze" ]] || die "run scripts/extra/depgraph/build.sh first"
G="$OUT/extra/depgraph"
LP=$(cd "$PROJ" && lake --keep-toolchain env printenv LEAN_PATH)

log "export the dependency graph of Main"
if (cd "$OUT/extra" && LEAN_PATH="$LP" /usr/bin/time -f 'wall %es, max RSS %M KB' "$B/.lake/build/bin/depgraph" "$G" Main); then
  ok "graph exported; self-check passed (see $G/meta.txt)"
else
  bad "export or its self-check failed"; finish
fi

# Declarations to report cone and exclusive sizes for: the final theorems and the three
# results of New.Main they are derived from. Add your own with QUERIES="name1 name2".
read -ra QUERIES <<< "riemannHypothesis LFunction_ne_zero_of_half_lt_re LFunction_eq_zero_re New.grh New.zeta_zeros_on_line New.zeros_on_line ${QUERIES:-}"
qargs=(); for q in "${QUERIES[@]}"; do qargs+=(--query "$q"); done

log "analyse"
{
  for root in riemannHypothesis LFunction_eq_zero_re; do
    echo "==================================================================== root: $root"
    "$B/depgraph_analyze" "$G" "$root" --depth 10 --min-pct 0.5 "${qargs[@]}"
    echo
  done
} > "$OUT/extra/depgraph-report.txt" && ok "report: $OUT/extra/depgraph-report.txt" || bad "analysis failed"
head -40 "$OUT/extra/depgraph-report.txt"
finish
