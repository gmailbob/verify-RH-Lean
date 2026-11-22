#!/usr/bin/env bash
# Step 0: check that this machine can run the full verification.
# Read-only. Prints PASS/WARN/FAIL lines and exits non-zero on any FAIL.
source "$(dirname "$0")/lib.sh"
log_to 00-check-machine.log

mkdir -p "$WORKDIR"
gb() { echo $(( $1 / 1024 / 1024 / 1024 )); }

log "platform"
echo "  $(uname -srm); $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
ok "architecture $LEAN_ARCH is supported (asset $LEAN_ASSET)"

log "required tools"
for t in bash curl tar gzip zstd sha256sum python3 git awk find xargs sort df free nproc; do
  if command -v "$t" >/dev/null; then ok "$t"; else bad "$t not installed"; fi
done
if python3 -I -c 'import sys; sys.exit(sys.version_info < (3, 8))'; then
  ok "python3 >= 3.8 ($(python3 --version 2>&1))"
else
  bad "python3 >= 3.8 required"
fi
[[ -x /usr/bin/time ]] && ok "GNU time (/usr/bin/time)" || bad "GNU time missing (package: time)"
command -v tmux >/dev/null && ok "tmux (for the long steps 5 and 7)" || warn "tmux not installed; recommended for steps 5 and 7 (e.g. sudo dnf install -y tmux)"
command -v elan >/dev/null && warn "elan is installed; these scripts ignore it and use the pinned release directly"

log "CPU"
cpus=$(nproc)
echo "  $cpus logical CPUs; JOBS=$JOBS"
(( cpus >= 16 )) && ok "$cpus CPUs" || warn "$cpus CPUs: the build will take well over a day"
(( JOBS <= cpus )) || warn "JOBS=$JOBS exceeds CPU count"

log "memory"
mem_b=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)
swap_b=$(awk '/SwapTotal/ {print $2 * 1024}' /proc/meminfo)
echo "  RAM $(gb "$mem_b") GiB, swap $(gb "$swap_b") GiB"
if (( $(gb $((mem_b + swap_b))) >= MIN_MEM_PLUS_SWAP_GB )); then
  ok "RAM + swap >= ${MIN_MEM_PLUS_SWAP_GB} GiB"
else
  bad "RAM + swap < ${MIN_MEM_PLUS_SWAP_GB} GiB. Add swap, e.g.:"
  echo "        sudo fallocate -l 64G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
fi
(( $(gb "$mem_b") / JOBS >= 1 )) || warn "less than 1 GiB RAM per job; consider lowering JOBS"
while read -r sf; do
  if grep -qE "^[[:space:]]*${sf}[[:space:]]" /etc/fstab 2>/dev/null; then
    ok "swapfile $sf is in /etc/fstab (survives a reboot)"
  else
    warn "swapfile $sf is not in /etc/fstab; a reboot turns it off. Add: $sf none swap defaults,nofail 0 0"
  fi
done < <(swapon --noheadings --show=NAME,TYPE 2>/dev/null | awk '$2 == "file" {print $1}')

log "disk at $WORKDIR"
free_kb=$(df -Pk "$WORKDIR" | awk 'NR==2 {print $4}')
free_gb=$(( free_kb / 1000 / 1000 ))
used_by_us_gb=$(( $(du -sk "$WORKDIR" 2>/dev/null | cut -f1) / 1000 / 1000 ))
avail_gb=$(( free_gb + used_by_us_gb ))
echo "  $(df -h "$WORKDIR" | awk 'NR==2 {print $1, $2" total,", $4" free"}'); already used by WORKDIR: ${used_by_us_gb} GB"
if   (( avail_gb >= REC_FREE_DISK_GB )); then ok "${avail_gb} GB available >= ${REC_FREE_DISK_GB} GB recommended"
elif (( avail_gb >= MIN_FREE_DISK_GB )); then warn "${avail_gb} GB available: above the ${MIN_FREE_DISK_GB} GB minimum but tight"
else bad "${avail_gb} GB available < ${MIN_FREE_DISK_GB} GB minimum (build outputs are ~1.1 TB)"; fi
ifree=$(df -Pi "$WORKDIR" | awk 'NR==2 {print $4}')
if [[ "$ifree" =~ ^[0-9]+$ ]] && (( ifree < MIN_FREE_INODES )); then
  bad "only $ifree free inodes (< $MIN_FREE_INODES)"
else
  ok "free inodes: $ifree"
fi
case "$(realpath "$WORKDIR")/" in
  "$REPO"/*) bad "WORKDIR is inside this repository; put it elsewhere" ;;
  *) ok "WORKDIR is outside the repository" ;;
esac

log "limits"
nofile=$(ulimit -n)
if [[ "$nofile" == unlimited ]] || (( nofile >= MIN_OPEN_FILES )); then ok "open files limit $nofile"; else bad "open files limit $nofile < $MIN_OPEN_FILES (ulimit -n)"; fi

mmc=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if (( mmc >= MIN_MAX_MAP_COUNT )); then
  ok "vm.max_map_count $mmc"
else
  bad "vm.max_map_count $mmc < $MIN_MAX_MAP_COUNT. Deep modules import >20k .olean files and Lean fails with"
  echo "        'failed to read file' (mmap ENOMEM). Fix, persistently:"
  echo "        printf 'vm.max_map_count = 1048576\\n' | sudo tee /etc/sysctl.d/99-lean-max-map-count.conf && sudo sysctl --system"
fi

log "network"
for u in "$SOURCE_BASE_URL/$ANNOUNCEMENT_FILE" "$LEAN_RELEASE_URL/$LEAN_ASSET" "https://github.com/leanprover-community/mathlib4"; do
  if curl -fsSLI --max-time 30 -o /dev/null "$u"; then ok "reachable: $u"; else bad "unreachable: $u"; fi
done

finish
