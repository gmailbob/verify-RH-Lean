#!/usr/bin/env bash
# Step 4: fetch the pinned dependencies (mathlib and its deps) and mathlib's
# prebuilt .olean cache, then check every checkout is exactly the pinned revision.
#
# Trust note: the mathlib cache consists of .olean files built by mathlib's CI.
# Step 7 (leanchecker --fresh) re-checks every declaration in them with the kernel,
# so after step 7 you no longer depend on that cache being honest.
source "$(dirname "$0")/lib.sh"
need_toolchain
need_project
log_to 04-fetch-deps.log

cd "$PROJ"   # lake must run from the project root

log "lake exe cache get (clones dependencies at the manifest revisions, downloads mathlib .oleans)"
lake --keep-toolchain exe cache get

log "verify dependency checkouts"
while read -r name rev url; do
  d="$PROJ/.lake/packages/$name"
  if [[ ! -d "$d/.git" && ! -f "$d/.git" ]]; then bad "$name: not checked out at $d"; continue; fi
  head=$(git -C "$d" rev-parse HEAD)
  [[ "$head" == "$rev" ]] && ok "$name at $rev" || bad "$name at $head, expected $rev"
  origin=$(git -C "$d" remote get-url origin 2>/dev/null || echo "?")
  [[ "${origin%.git}" == "${url%.git}" ]] || warn "$name origin is $origin, manifest says $url"
  [[ -z "$(git -C "$d" status --porcelain --untracked-files=no)" ]] && ok "$name has no modified tracked files" || bad "$name has local modifications"
done < "$REPO/expected/lake-manifest.revs"

extra=$(comm -13 <(awk '{print $1}' "$REPO/expected/lake-manifest.revs" | sort) <(ls "$PROJ/.lake/packages" | sort))
[[ -z "$extra" ]] && ok "no unexpected packages" || bad "unexpected packages: $extra"

log "toolchain files of the dependencies"
# Lake builds every package with the root project's toolchain. Only mathlib's file
# matters: its cache was built with it, so it must equal ours.
mt=$(tr -d '[:space:]' < "$PROJ/.lake/packages/mathlib/lean-toolchain")
[[ "$mt" == "leanprover/lean4:v$LEAN_VERSION" ]] && ok "mathlib toolchain $mt (cache is compatible)" \
  || bad "mathlib toolchain is $mt; its cache will not match v$LEAN_VERSION"
for d in "$PROJ"/.lake/packages/*/; do
  [[ "$(basename "$d")" == mathlib || ! -f "$d/lean-toolchain" ]] && continue
  echo "  info  $(basename "$d") declares $(tr -d '[:space:]' < "$d/lean-toolchain"); built with v$LEAN_VERSION"
done

log "mathlib cache completeness"
m="$PROJ/.lake/packages/mathlib"
missing=$(comm -23 <(cd "$m" && { find Mathlib -name '*.lean'; echo Mathlib.lean; } | sed 's/\.lean$//' | sort) \
                   <(cd "$m/.lake/build/lib/lean" 2>/dev/null && find Mathlib Mathlib.olean -name '*.olean' | sed 's/\.olean$//' | sort) | wc -l)
total=$(cd "$m" && find Mathlib -name '*.lean' | wc -l)
(( missing == 0 )) && ok "every Mathlib module ($((total + 1))) has a cached .olean" \
  || bad "$missing of $((total + 1)) Mathlib modules have no cached .olean"
echo "  disk used by .lake so far: $(du -sh "$PROJ/.lake" | cut -f1)"

finish
