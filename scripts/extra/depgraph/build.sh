#!/usr/bin/env bash
# Build the dependency-graph tools into $WORKDIR/out/extra/depgraph-build (outside the repo):
#   depgraph          native Lean executable (DepGraph.lean), needs only Lean core to build
#   depgraph_analyze  C program; built with a system cc if present, else with Lean's leanc
# Then runs the analyzer's brute-force tests (test_analyze.py).
source "$(dirname "$0")/../../lib.sh"
need_toolchain

SRC="$REPO/scripts/extra/depgraph"
B="$OUT/extra/depgraph-build"
mkdir -p "$B"

log "analyzer"
if command -v cc >/dev/null; then CC=cc; else CC="$LEAN_HOME/bin/leanc"; fi
"$CC" -O2 -Wall -Wextra -o "$B/depgraph_analyze" "$SRC/depgraph_analyze.c" && ok "built with $CC" || { bad "compile failed"; finish; }
if python3 -I "$SRC/test_analyze.py" "$B/depgraph_analyze" 400 40 | sed 's/^/  /' \
   && python3 -I "$SRC/test_analyze.py" "$B/depgraph_analyze" 100 150 | sed 's/^/  /'; then
  ok "analyzer agrees with brute force on 500 random graphs"
else
  bad "analyzer tests failed"; finish
fi

log "exporter"
cp "$SRC/DepGraph.lean" "$B/DepGraph.lean"
echo "leanprover/lean4:v$LEAN_VERSION" > "$B/lean-toolchain"
cat > "$B/lakefile.toml" <<'EOF'
name = "depgraph"
defaultTargets = ["depgraph"]

[[lean_exe]]
name = "depgraph"
root = "DepGraph"
supportInterpreter = true
EOF
(cd "$B" && lake --keep-toolchain build 2>&1 | tail -5) && [[ -x "$B/.lake/build/bin/depgraph" ]] \
  && ok "built $B/.lake/build/bin/depgraph" || { bad "exporter build failed"; finish; }
finish
