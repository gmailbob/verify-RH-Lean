#!/usr/bin/env bash
# Block until something worth reacting to happens during a long step (5 or 7),
# print ONE line describing it, and exit. Meant to be re-armed after each event.
#
# Usage: watch-step.sh <name> <exit-file> <lake-log|-> [options]
#   --progress PCT     also stop when Lake's job counter n reaches PCT percent of the total
#   --total N          expected final job count (Lake's own N grows while it discovers jobs,
#                      so n/N is meaningless early on). Default: Lake's current N.
#   --stall-min M      stop if progress has not moved for M minutes   (default 60)
#   --disk-min-gb G    stop if free disk at $WORKDIR drops below G GB  (default 150)
#   --swap-max-gb G    stop if swap in use exceeds G GiB               (default 40)
#   --poll S           seconds between checks                          (default 60)
#
# Events, first one wins:
#   DONE        <exit-file> appeared (the wrapper writes the step's exit status there)
#   FAILED_JOB  a Lake job failed ("✖" or "error:" at line start in the log)
#   DISK_LOW / SWAP_HIGH / STALL / PROGRESS
set -uo pipefail
name="$1" exitf="$2" llog="$3"; shift 3
target="" total_override="" stall_min=60 disk_min=150 swap_max=40 poll=60
while (( $# )); do
  case "$1" in
    --progress) target="$2"; shift 2 ;;
    --total) total_override="$2"; shift 2 ;;
    --stall-min) stall_min="$2"; shift 2 ;;
    --disk-min-gb) disk_min="$2"; shift 2 ;;
    --swap-max-gb) swap_max="$2"; shift 2 ;;
    --poll) poll="$2"; shift 2 ;;
    *) echo "watch-step: unknown option $1"; exit 2 ;;
  esac
done
: "${WORKDIR:?set WORKDIR}"

now() { date -u +%FT%TZ; }
off=0
[[ "$llog" != - && -f "$llog" ]] && off=$(stat -c %s "$llog")   # only new failures count
last_prog="" last_move=$(date +%s)

while :; do
  if [[ -f "$exitf" ]]; then echo "DONE $name exit=$(cat "$exitf") at $(now)"; exit 0; fi

  free_gb=$(( $(df -Pk "$WORKDIR" | awk 'NR==2 {print $4}') / 1000000 ))
  swap_gib=$(free -k | awk '/^Swap:/ {printf "%d", $3 / 1048576}')
  prog=""
  if [[ "$llog" != - && -f "$llog" ]]; then
    size=$(stat -c %s "$llog")
    if (( size > off )); then
      hit=$(tail -c +$((off + 1)) "$llog" | head -c $((size - off)) | grep -aE -m 3 '^(✖|error:)' || true)
      if [[ -n "$hit" ]]; then
        echo "FAILED_JOB $name at $(now): $(echo "$hit" | tr '\n' ' ' | cut -c1-400)"; exit 0
      fi
      off=$size
    fi
    prog=$(tail -c 262144 "$llog" | grep -aoE '\[[0-9]+/[0-9]+\]' | tail -1 | tr -d '[]')
  fi

  (( free_gb < disk_min )) && { echo "DISK_LOW $name: ${free_gb} GB free at $(now) (progress ${prog:-?})"; exit 0; }
  (( swap_gib > swap_max )) && { echo "SWAP_HIGH $name: ${swap_gib} GiB swap in use at $(now) (progress ${prog:-?})"; exit 0; }

  if [[ -n "$prog" && "$prog" != "$last_prog" ]]; then
    last_prog="$prog"; last_move=$(date +%s)
  elif (( $(date +%s) - last_move > stall_min * 60 )); then
    echo "STALL $name: no progress change for ${stall_min} min (at ${prog:-?}) at $(now)"; exit 0
  fi

  if [[ -n "$target" && -n "$prog" ]]; then
    n=${prog%/*} total=${total_override:-${prog#*/}}
    if (( total > 0 && n * 100 >= target * total )); then
      echo "PROGRESS $name reached ${prog} ($(( n * 1000 / total ))‰) at $(now); ${free_gb} GB free, swap ${swap_gib} GiB"; exit 0
    fi
  fi
  sleep "$poll"
done
