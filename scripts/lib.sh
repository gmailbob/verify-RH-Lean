# shellcheck shell=bash
# Shared setup for all numbered scripts. Source it; do not execute it.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "$REPO/config.sh"

SRC="$WORKDIR/src"              # downloaded sources (untrusted)
CLONE="$SRC/grh-lean"           # fresh clone of $SOURCE_REPO_URL at $SOURCE_COMMIT
PROJ="$CLONE/$SOURCE_SUBDIR"    # the Lake project
TC="$WORKDIR/toolchain"         # Lean release
OUT="$WORKDIR/out"              # logs, hash lists, reports from each step

case "$(uname -m)" in
  x86_64)        LEAN_ARCH=x86_64;  LEAN_ASSET="lean-${LEAN_VERSION}-linux.tar.zst" ;;
  aarch64|arm64) LEAN_ARCH=aarch64; LEAN_ASSET="lean-${LEAN_VERSION}-linux_aarch64.tar.zst" ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
LEAN_SHA256_VAR="LEAN_SHA256_${LEAN_ARCH}"
LEAN_SHA256="${!LEAN_SHA256_VAR}"
LEAN_HOME="$TC/${LEAN_ASSET%.tar.zst}"
export PATH="$LEAN_HOME/bin:$PATH"

mkdir -p "$OUT"

# ---- helpers
c_ok=$'\e[32m'; c_bad=$'\e[31m'; c_warn=$'\e[33m'; c_off=$'\e[0m'
[[ -t 1 ]] || { c_ok=; c_bad=; c_warn=; c_off=; }

FAILS=0
WARNS=0
log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()   { printf '  %sPASS%s  %s\n' "$c_ok" "$c_off" "$*"; }
bad()  { printf '  %sFAIL%s  %s\n' "$c_bad" "$c_off" "$*"; FAILS=$((FAILS + 1)); }
warn() { printf '  %sWARN%s  %s\n' "$c_warn" "$c_off" "$*"; WARNS=$((WARNS + 1)); }
die()  { printf '%sERROR%s %s\n' "$c_bad" "$c_off" "$*" >&2; exit 1; }

# sha256_is <file> <expected>
sha256_is() { [[ "$(sha256sum "$1" | cut -d' ' -f1)" == "$2" ]]; }

# Print a summary and exit non-zero if any check failed.
finish() {
  echo
  if (( FAILS > 0 )); then
    printf '%s%d check(s) FAILED%s, %d warning(s). Do not continue.\n' "$c_bad" "$FAILS" "$c_off" "$WARNS"
    exit 1
  fi
  printf '%sAll checks passed%s (%d warning(s)).\n' "$c_ok" "$c_off" "$WARNS"
  exit 0
}

need_toolchain() {
  [[ -x "$LEAN_HOME/bin/lean" ]] || die "toolchain missing; run scripts/01-install-toolchain.sh"
}
# Lean memory-maps every imported .olean file. If a process runs out of mappings
# (vm.max_map_count), Lean fails with "failed to read file '....olean'" although the file is
# intact (mmap returns ENOMEM). Raise the limit if you see that.
need_max_map_count() {
  local m; m=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
  (( m >= MIN_MAX_MAP_COUNT )) || die "vm.max_map_count is $m, need >= $MIN_MAX_MAP_COUNT (see scripts/00-check-machine.sh)"
}
need_project() {
  [[ -f "$PROJ/lakefile.toml" ]] || die "project missing; run scripts/02-fetch-source.sh"
}

# pinned_checkout <url> <dir> <full-commit-sha>: clone if needed, check out exactly that commit,
# and check that no tracked file is modified. Records PASS/FAIL lines.
pinned_checkout() {
  local url="$1" dir="$2" rev="$3"
  [[ -d "$dir/.git" ]] || git clone --quiet "$url" "$dir"
  git -C "$dir" fetch --quiet origin "$rev" 2>/dev/null || git -C "$dir" fetch --quiet origin
  git -C "$dir" -c advice.detachedHead=false checkout --quiet --detach "$rev"
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$rev" ]] && ok "$(basename "$dir") at $rev" || bad "$(basename "$dir") not at $rev"
  [[ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ]] \
    && ok "$(basename "$dir") has no modified tracked files" || bad "$(basename "$dir") has local modifications"
}

# start_monitor <csv> [interval-seconds] [lake-log]: sample disk/memory/load, the largest
# number of memory mappings held by any Lean process (the quantity vm.max_map_count limits),
# and lake [n/N] progress if a log is given, in the background until stop_monitor.
start_monitor() {
  local csv="$1" iv="${2:-300}" plog="${3:-}"
  # append, so a resumed run (e.g. after a reboot) keeps the earlier samples
  [[ -s "$csv" ]] || echo "utc,disk_used_gb,disk_avail_gb,mem_used_gib,swap_used_gib,load1,progress,max_maps" > "$csv"
  (
    set +e +o pipefail   # a failed sample (e.g. no progress line yet) must not kill the monitor
    while :; do
      read -r du da < <(df -Pk "$WORKDIR" | awk 'NR==2 {printf "%d %d\n", $3/1e6, $4/1e6}')
      read -r mu su < <(free -k | awk '/^Mem:/ {m=$3} /^Swap:/ {s=$3} END {printf "%.1f %.1f\n", m/1048576, s/1048576}')
      prog=""
      [[ -n "$plog" && -f "$plog" ]] && prog=$(tail -c 262144 "$plog" | grep -oE '\[[0-9]+/[0-9]+\]' | tail -1 | tr -d '[]')
      mm=0
      for p in $(pgrep -x 'lean|leanchecker|leanexport' 2>/dev/null); do
        n=$( { wc -l < "/proc/$p/maps"; } 2>/dev/null ) || continue   # the process may have exited
        (( ${n:-0} > mm )) && mm=$n
      done
      echo "$(date -u +%FT%TZ),$du,$da,$mu,$su,$(cut -d' ' -f1 /proc/loadavg),$prog,$mm" >> "$csv"
      sleep "$iv"
    done
  ) &
  MONITOR_PID=$!
}
stop_monitor() { if [[ -n "${MONITOR_PID:-}" ]]; then kill "$MONITOR_PID" 2>/dev/null || true; fi; }

# Tee all output of the calling script to $OUT/<name>.log as well.
log_to() {
  local f="$OUT/$1"
  # tee ignores Ctrl-C/TERM (ignored signals survive exec), so an interrupted step can still
  # write its summary; otherwise tee dies first and the step is killed by SIGPIPE.
  exec > >(trap '' INT TERM; exec tee -a "$f") 2>&1
  echo "=== $(date -u +%FT%TZ)  $(basename "$0") $*  (host $(hostname), WORKDIR=$WORKDIR)"
}
