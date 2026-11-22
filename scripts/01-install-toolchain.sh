#!/usr/bin/env bash
# Step 1: install the pinned official Lean release and check that it is authentic.
#
# Checks: release-asset sha256 against the pin in config.sh, against the digest
# GitHub publishes for the asset, and the commit the binary reports against the
# v$LEAN_VERSION tag. Then smoke-tests lean, lake and leanchecker.
source "$(dirname "$0")/lib.sh"
log_to 01-install-toolchain.log

mkdir -p "$TC"
tarball="$TC/$LEAN_ASSET"

log "download $LEAN_ASSET"
if [[ -s "$tarball" ]]; then
  echo "  already present"
else
  curl -fSL --retry 5 --retry-delay 5 -o "$tarball.partial" "$LEAN_RELEASE_URL/$LEAN_ASSET"
  mv "$tarball.partial" "$tarball"
fi

log "authenticity"
actual=$(sha256sum "$tarball" | cut -d' ' -f1)
echo "  sha256 $actual"
if [[ "$actual" == "$LEAN_SHA256" ]]; then ok "matches pin in config.sh"; else bad "does not match pin $LEAN_SHA256"; fi

api=$(curl -fsSL --max-time 60 "https://api.github.com/repos/leanprover/lean4/releases/tags/v${LEAN_VERSION}" || true)
if [[ -n "$api" ]]; then
  gh_digest=$(python3 -I -c '
import json, sys
for a in json.load(sys.stdin)["assets"]:
    if a["name"] == sys.argv[1]:
        print((a.get("digest") or "").replace("sha256:", "", 1))
' "$LEAN_ASSET" <<<"$api")
  if [[ "$gh_digest" == "$actual" ]]; then ok "matches GitHub release asset digest"; else bad "GitHub digest is '${gh_digest:-missing}'"; fi
  tag_sha=$(curl -fsSL --max-time 60 "https://api.github.com/repos/leanprover/lean4/git/ref/tags/v${LEAN_VERSION}" \
            | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["object"]["sha"])' || true)
  if [[ "$tag_sha" == "$LEAN_COMMIT" ]]; then ok "tag v$LEAN_VERSION points at pinned commit $LEAN_COMMIT"; else bad "tag v$LEAN_VERSION points at '${tag_sha:-?}'"; fi
else
  warn "GitHub API unreachable (rate limit?); relying on the pinned hash only"
fi
(( FAILS == 0 )) || finish

log "extract"
if [[ -x "$LEAN_HOME/bin/lean" ]]; then
  echo "  already extracted at $LEAN_HOME"
else
  tar --use-compress-program=unzstd -xf "$tarball" -C "$TC"
fi

log "binaries"
v=$(lean --version)
echo "  $v"
[[ "$v" == *"version $LEAN_VERSION,"* ]] && ok "lean reports version $LEAN_VERSION" || bad "lean version mismatch"
[[ "$v" == *"commit $LEAN_COMMIT"* ]] && ok "lean reports commit $LEAN_COMMIT" || bad "lean commit mismatch"
lv=$(lake --version); echo "  $lv"
[[ "$lv" == *"Lean version $LEAN_VERSION"* ]] && ok "lake matches" || bad "lake version mismatch"
for b in lean lake leanchecker; do
  [[ "$(command -v $b)" == "$LEAN_HOME/bin/$b" ]] && ok "$b resolves to the pinned toolchain" || bad "$b resolves to $(command -v $b)"
done

log "smoke tests"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/Smoke.lean" <<'EOF'
theorem smoke (a b : Nat) : a + b = b + a := Nat.add_comm a b
#print axioms smoke
EOF
out=$(cd "$tmp" && lean Smoke.lean 2>&1) || true
echo "  $out"
[[ "$out" == *"does not depend on any axioms"* ]] && ok "lean elaborates and checks a theorem" || bad "lean smoke test"
if (cd "$tmp" && leanchecker --fresh Init.Prelude); then ok "leanchecker --fresh Init.Prelude"; else bad "leanchecker smoke test"; fi

echo
echo "To use this toolchain in your shell:  export PATH=\"$LEAN_HOME/bin:\$PATH\""
finish
