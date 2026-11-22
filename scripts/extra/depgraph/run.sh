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

QUERIES=(riemannHypothesis rhOfAll allChi claimAll critAll
  UpperTheory.FinalTheorems.everyCharacter UpperTheory.FinalTheorems.everyCharacter_of_row
  UpperTheory.Gal.Int.galoisLocalGlobalStrong_recParameter UpperTheory.Gal.Int.galoisRepresentations_of_thetaLift
  UpperTheory.LiteratureTheorems.every_character_of_literature_of_vWin
  UpperTheory.Lit.every_character_of_theta_integrals_local_matching
  UpperTheory.One.vwin_of_row UpperTheory.One.Join.automorphic_window_of_inputs UpperTheory.Zero.LLC.recTExists
  Formalism.VW.rh_of_every Formalism.VW.rh_of_right Formalism.VW.critLine Claim.strip Claim.zeta)
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
