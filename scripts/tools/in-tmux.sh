#!/usr/bin/env bash
# Run a long step (5 or 7) detached in tmux, so it survives logout and a closed terminal.
#
# Usage: scripts/tools/in-tmux.sh <step-script> [session-name]
#   e.g. scripts/tools/in-tmux.sh scripts/05-build.sh        (session "05-build")
#
# - When the step ends, its exit status is written to $WORKDIR/out/<step>.exit and the
#   pane stays open for inspection. Attach with:  tmux attach -t <session>
# - To stop the step, press Ctrl-C in its pane. The wrapper traps the interrupt, so the
#   step still writes its summary and the .exit file. (Without the trap the interrupt
#   also kills the wrapper shell, and no summary or exit status is written.)
# - Do not edit the step script while it runs: bash reads scripts incrementally, by byte
#   offset, so an edit can make it resume in the wrong place when the long command ends.
# - Wait for a step from another shell with scripts/tools/watch-step.sh.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../config.sh
source "$REPO/config.sh"

step="$(realpath "${1:?usage: in-tmux.sh <step-script> [session-name]}")"
[[ -x "$step" ]] || { echo "not an executable script: $step" >&2; exit 1; }
name="$(basename "$step" .sh)"
session="${2:-$name}"
command -v tmux >/dev/null || { echo "tmux is not installed" >&2; exit 1; }
if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session '$session' already exists; attach with: tmux attach -t $session" >&2; exit 1
fi

# tmux sessions start with the tmux server's environment, not ours: forward the kit's settings.
fwd=""
for v in JOBS UPTO FORCE REEXPORT CHECK_JOBS REPLAY_TARGET SELFTEST_ONLY; do
  [[ -n "${!v:-}" ]] && fwd+="export $v='${!v}'; "
done

mkdir -p "$WORKDIR/out"
exitf="$WORKDIR/out/$name.exit"
rm -f "$exitf"
tmux new-session -d -s "$session" -c "$REPO" \
  "trap 'echo \"[interrupt received; letting the step finish up]\"' INT
   export WORKDIR='$WORKDIR'; $fwd
   '$step'
   echo \$? > '$exitf'
   echo; echo \"[$name exited with status \$(cat '$exitf'); shell kept open]\"
   exec bash"
echo "started $name in tmux session '$session'${fwd:+ with: $fwd}"
echo "  attach:      tmux attach -t $session   (detach: Ctrl-b d)"
echo "  exit status: $exitf (written when it ends)"
