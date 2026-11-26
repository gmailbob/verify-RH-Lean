#!/usr/bin/env bash
# Build the excerpt "Introduction and Part 1" (part1-handout.tex) with the numbering of the
# full paper. Run after a full build of main.tex into build/ (it reads build/main.aux).
# Usage: tools/make_part1.sh /path/to/grh-lean/grh/src     -> build/GRH-reading-part1.pdf
set -eu
src="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
mkdir -p build/part1
python3 tools/make_leanindex.py "$src" build/leanindex-part1.tex sections/s01-intro.tex \
  sections/s02-zeros.tex sections/s03-setup.tex sections/data.tex sections/s04-main.tex
rm -f build/extlabels.tex
latexmk -g -pdf -interaction=nonstopmode -outdir=build/part1 part1-handout.tex > build/part1/latexmk.out 2>&1
# Labels of the full paper that the excerpt does not define itself (Sections 6-22, Appendices B, C).
python3 - <<'PY'
import re
def labels(p):
    d = {}
    for line in open(p, encoding='utf-8', errors='replace'):
        m = re.match(r'\\newlabel\{([^}]*)\}', line)
        if m: d[m.group(1)] = line
    return d
own, full = labels('build/part1/part1-handout.aux'), labels('build/main.aux')
open('build/extlabels.tex', 'w', encoding='utf-8').write(
    ''.join(v for k, v in full.items() if k not in own))
def num(l):
    m = re.match(r'\\newlabel\{[^}]*\}\{\{([^}]*)\}', l)
    return m.group(1) if m else None
bad = [k for k in own if k in full and num(own[k]) != num(full[k])]
print(len(own), 'labels in the excerpt;', len(full) - len(own), 'taken from the full paper;',
      'numbering differences:', bad)
PY
latexmk -g -pdf -interaction=nonstopmode -outdir=build/part1 part1-handout.tex > build/part1/latexmk.out 2>&1
log=build/part1/part1-handout.log
grep -o 'Output written on .*' "$log"
echo "undefined references: $(grep -c 'Reference .* undefined' "$log" || true)"
cp build/part1/part1-handout.pdf build/GRH-reading-part1.pdf
echo "-> build/GRH-reading-part1.pdf"
