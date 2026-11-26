#!/usr/bin/env bash
# Compile one section on its own to catch LaTeX errors.
# Usage: tools/check_section.sh <id>      (compiles sections/<id>.tex)
# References to labels of other sections show up as undefined; that is expected.
set -u
id="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/sec-$id"
mkdir -p "$out"
cat > "$out/wrap.tex" <<EOF
\\input{$root/preamble.tex}
\\begin{document}
\\input{$root/sections/$id.tex}
\\end{document}
EOF
cd "$out" && TEXINPUTS="$root:" latexmk -pdf -interaction=nonstopmode -halt-on-error wrap.tex > latexmk.out 2>&1
status=$?
if [ $status -ne 0 ]; then
  echo "COMPILE FAILED for $id"
  grep -n -A8 '^!' wrap.log | head -60
  exit 1
fi
pages=$(grep -o 'Output written on wrap.pdf ([0-9]* page' wrap.log | grep -o '[0-9]*')
echo "OK: $id compiles, $pages pages (as a standalone file)"
echo "overfull boxes: $(grep -c '^Overfull' wrap.log)"
echo "undefined references (cross-section ones are expected):"
grep -o "Reference \`[^']*' on page [0-9]*" wrap.log | sort -u | head -20
