#!/usr/bin/env bash
# Copy the small, claim-backing outputs of a run from $WORKDIR/out into evidence/ (or <dest>),
# so they can be committed next to REPORT.md. Text files are cleaned: colour codes are
# stripped, and the machine's hostname (on AWS it encodes the private IP and region) is
# replaced with <host>. Large or easily regenerated outputs are deliberately left out; see
# evidence/README.md for what is included and why.
#
# Usage: scripts/tools/collect-evidence.sh [dest]      (default: <repo>/evidence)
source "$(dirname "$0")/../lib.sh"
DEST="${1:-$REPO/evidence}"
mkdir -p "$DEST"

HOST_FQDN=$(hostname -f 2>/dev/null || hostname)
HOST_SHORT=$(hostname -s 2>/dev/null || hostname)
clean() {  # clean <src> <dst>: copy a text file, stripping ANSI codes and host names
  mkdir -p "$(dirname "$2")"
  sed -E -e 's/\x1b\[[0-9;]*m//g' \
         -e 's/ip-[0-9]+-[0-9]+-[0-9]+-[0-9]+(\.[a-z0-9-]+)*\.compute\.internal/<host>/g' \
         -e "s/${HOST_FQDN//./\\.}/<host>/g" -e "s/(^|[^A-Za-z0-9])${HOST_SHORT}([^A-Za-z0-9]|$)/\\1<host>\\2/g" \
         "$1" > "$2"
}
take() {  # take <src relative to $OUT> <dst relative to $DEST>
  if [[ -f "$OUT/$1" ]]; then clean "$OUT/$1" "$DEST/$2"; ok "$2"; else warn "missing $OUT/$1"; fi
}
takebin() {
  if [[ -f "$OUT/$1" ]]; then mkdir -p "$(dirname "$DEST/$2")"; cp -f "$OUT/$1" "$DEST/$2"; ok "$2"; else warn "missing $OUT/$1"; fi
}

log "step logs"
for f in 00-check-machine 01-install-toolchain 02-fetch-source 04-fetch-deps 05-build 06-audit \
         07-kernel-replay 08-verify-sources-unchanged 09-independent-kernel extra-depgraph; do
  take "$f.log" "logs/$f.log"
done

log "per-claim files"
take scan.txt                     scan/scan.txt
take scan.json                    scan/scan.json
take build-summary.txt            build/build-summary.txt
take build-monitor.csv            build/build-monitor.csv
take audit/selftest.txt           audit/selftest.txt
take audit/statements.txt         audit/statements.txt
take audit.txt                    audit/audit.txt
take replay.log                   replay/replay.log
take replay-monitor.csv           replay/replay-monitor.csv
take replay-progress.csv          replay/replay-progress.csv
take con-leche-solution-mit.log   independent-kernel/con-leche-solution-mit.log
take solution-mit.ndjson.sha256   independent-kernel/solution-mit.ndjson.sha256
take export-memtrend.csv          independent-kernel/own-export-memtrend.csv
take olean-vs-mit.txt             build-match/olean-vs-mit.txt
take manifest-vs-mit.txt          build-match/manifest-vs-mit.txt
takebin project-oleans.sha256.zst build-match/project-oleans.sha256.zst
take extra/depgraph-report.txt    proof-structure/depgraph-report.txt
take extra/depgraph/meta.txt      proof-structure/depgraph-meta.txt
take extra/proof-tree.txt         proof-structure/proof-tree.txt

log "machine description"
{
  echo "# collected $(date -u +%FT%TZ)"
  echo "kernel:        $(uname -srm)"
  echo "os:            $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
  tok=$(curl -fsS -X PUT --max-time 2 http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null || true)
  [[ -n "$tok" ]] && echo "instance type: $(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $tok" http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null)"
  model=$(lscpu 2>/dev/null | awk -F: '/^(BIOS )?Model name/ {gsub(/^ +| +$/, "", $2); if ($2 != "" && $2 != "-") {print $2; exit}}')
  echo "cpus:          $(nproc)${model:+ ($model)}"
  echo "memory:        $(free -g | awk '/^Mem:/ {print $2" GiB RAM"} /^Swap:/ {print "               "$2" GiB swap"}')"
  echo "disk:          $(lsblk -dno SIZE,MODEL "$(df -P "$WORKDIR" | awk 'NR==2 {print $1}' | sed -E 's/p?[0-9]+$//')" 2>/dev/null | xargs)"
  echo "filesystem:    $(df -PTh "$WORKDIR" | awk 'NR==2 {print $2", "$3" total"}')"
  echo "vm.max_map_count: $(sysctl -n vm.max_map_count 2>/dev/null)"
  echo "lean:          $("$LEAN_HOME/bin/lean" --version 2>/dev/null)"
  echo "JOBS:          $JOBS"
} > "$DEST/machine.txt"
ok "machine.txt"

log "hashes of the third-party files we compared against (not copied)"
{
  echo "# sha256 of third-party files this run read, with where they came from. Fetched 2026-11-21/22."
  echo "# The files themselves are not redistributed here."
  R="$OUT/reference"
  if [[ -d "$R/mit" ]]; then
    for f in $(cd "$R/mit" && ls); do
      url="https://math.mit.edu/~drew/grh/$f"; [[ "$f" == index.html ]] && url="https://math.mit.edu/~drew/grh/"
      echo "$(sha256sum "$R/mit/$f" | cut -d' ' -f1)  $url"
    done
  fi
  if [[ -d "$R/github-io" ]]; then
    (cd "$R/github-io" && command find . -type f | sort) | while read -r f; do
      f="${f#./}"; url="https://proveriemannhypothesis.github.io/artifacts/$f"
      [[ "$f" == index.html ]] && url="https://proveriemannhypothesis.github.io/"
      echo "$(sha256sum "$R/github-io/$f" | cut -d' ' -f1)  $url"
    done
  fi
  if [[ -d "$R/deicyde" ]]; then
    for f in $(cd "$R/deicyde" && ls); do
      echo "$(sha256sum "$R/deicyde/$f" | cut -d' ' -f1)  https://raw.githubusercontent.com/Deicyde/riemann-hypothesis/HEAD/$f  (HEAD at fetch time)"
    done
  fi
  echo "$REFERENCE_EXPORT_ZST_SHA256  $REFERENCE_EXPORT_URL  (verified by step 9)"
  echo "$REFERENCE_EXPORT_SHA256  solution.ndjson, unpacked from the above  (verified by step 9)"
} > "$DEST/third-party.sha256"
ok "third-party.sha256"

log "check: nothing identifying left"
if grep -rlE "compute\.internal|${HOST_SHORT}" "$DEST" --include='*.log' --include='*.txt' --include='*.csv' --include='*.json' 2>/dev/null | grep -v README.md; then
  bad "host names remain in the files above"
else
  ok "no host names in the collected text files"
fi
echo "  total: $(du -sh "$DEST" | cut -f1)"
finish
