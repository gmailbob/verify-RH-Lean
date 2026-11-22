"""Validate a tarball before extracting it. Reads metadata only.

Usage: python3 -I check_tar.py <archive.tar.gz> <expected-root-dir> <expected-file-count>

Fails if any member is not a regular file or directory (no symlinks, hard links,
devices, FIFOs), has an absolute path or a '..' component, lies outside the
expected root directory, or if the regular-file count differs from the expectation.
"""
import sys
import tarfile
from collections import Counter

path, root, expected = sys.argv[1], sys.argv[2], int(sys.argv[3])
problems = []
files = dirs = 0
exts = Counter()
total = 0

with tarfile.open(path, "r:gz") as tf:
    for m in tf:
        name = m.name
        parts = name.split("/")
        if name.startswith("/") or ".." in parts:
            problems.append(f"unsafe path: {name}")
        if parts[0] != root:
            problems.append(f"outside {root}/: {name}")
        if m.isfile():
            files += 1
            total += m.size
            exts[name.rsplit(".", 1)[-1] if "." in parts[-1] else "(none)"] += 1
        elif m.isdir():
            dirs += 1
        else:
            problems.append(f"not a regular file or directory (type {m.type!r}): {name}")
        if len(problems) > 50:
            break

print(f"regular files: {files}  directories: {dirs}  uncompressed bytes: {total}")
print("by extension:", dict(exts.most_common()))
for p in problems[:50]:
    print("PROBLEM", p)
if files != expected:
    print(f"PROBLEM expected {expected} regular files, found {files}")
sys.exit(1 if problems or files != expected else 0)
