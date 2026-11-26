"""Compare our compiled .olean files with a third-party manifest of their hashes.

Usage: python3 -I compare_olean_manifest.py <build-lib-dir> <manifest.sha256> <our-src-path> [workers]
  build-lib-dir  e.g. $PROJ/.lake/build/lib/lean
  manifest       lines "<sha256>  ./<Module/Path>.olean", e.g. another run's
                 evidence/build/project-oleans.sha256.zst, unpacked
  our-src-path   absolute path of our src/ dir as Lean saw it, e.g. $PROJ/src/

Lean stores the absolute source path next to each saved linter message, so a file
can only match a build made at another path if it contains no path. This reports, for
each file: hash match or not, and whether our file contains our source path. Expected
for a faithful rebuild: every path-free file matches; every mismatch contains our path.

Each file is dropped from the page cache after hashing (posix_fadvise DONTNEED), so a
concurrent job (e.g. the kernel replay) keeps its cached data.
"""
import hashlib, os, sys
from multiprocessing import Pool

lib, manifest, our_src = sys.argv[1], sys.argv[2], sys.argv[3].encode()
workers = int(sys.argv[4]) if len(sys.argv) > 4 else 4

def work(rel):
    p = os.path.join(lib, rel)
    try:
        fd = os.open(p, os.O_RDONLY)
    except FileNotFoundError:
        return rel, None, False
    try:
        data = b""
        chunks = []
        while True:
            b = os.read(fd, 1 << 22)
            if not b: break
            chunks.append(b)
        data = b"".join(chunks)
        os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
    finally:
        os.close(fd)
    return rel, hashlib.sha256(data).hexdigest(), our_src in data

theirs = {}
for line in open(manifest):
    h, path = line.split(None, 1)
    theirs[path.strip().removeprefix("./") if hasattr(str, "removeprefix") else path.strip()[2:]] = h

match = mismatch = missing = 0
match_with_path = mismatch_without_path = 0
examples = []
with Pool(workers) as pool:
    for rel, h, has_path in pool.imap_unordered(work, sorted(theirs), chunksize=64):
        if h is None:
            missing += 1; continue
        if h == theirs[rel]:
            match += 1
            match_with_path += has_path
        else:
            mismatch += 1
            if not has_path:
                mismatch_without_path += 1
                if len(examples) < 10: examples.append(rel)
ours_total = sum(1 for r, _, fs in os.walk(lib) for f in fs if f.endswith(".olean"))
print(f"manifest entries: {len(theirs)}   our .olean files: {ours_total}   missing on our side: {missing}")
print(f"identical: {match}   different: {mismatch}")
print(f"  identical files containing our path:      {match_with_path}   (expected 0)")
print(f"  different files NOT containing our path:  {mismatch_without_path}   (expected 0)")
for e in examples: print("    unexplained difference:", e)
sys.exit(0 if (missing == 0 and mismatch_without_path == 0 and match_with_path == 0) else 1)
