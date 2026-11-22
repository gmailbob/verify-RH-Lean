#!/usr/bin/env bash
# Step 3: lexical audit of the extracted source (no code from the tree is run).
# Fails if any token that could bypass the kernel appears in code.
# Full report: $OUT/scan.txt ; machine-readable summary: $OUT/scan.json
source "$(dirname "$0")/lib.sh"
need_project

log "scanning $PROJ (takes a minute or two)"
if python3 -I "$REPO/scripts/tools/scan_source.py" "$PROJ" "$OUT/scan.json" > "$OUT/scan.txt"; then
  rc=0
else
  rc=$?
fi
sed -n '/^A\. HARD-FAIL/,/^B\./p' "$OUT/scan.txt" | head -40
sed -n '/^RESULT/,$p' "$OUT/scan.txt"
echo
echo "Full report: $OUT/scan.txt  (read sections B and E)"
exit $rc
