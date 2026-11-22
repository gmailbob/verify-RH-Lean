"""Print `sha256sum`-style lines for every regular file inside a .tar.gz, with
paths relative to the archive's root directory ("./path"), sorted by path.
Streams the archive; extracts nothing.

Usage: python3 -I tar_hashes.py <archive.tar.gz> <root-dir>
"""
import hashlib
import sys
import tarfile

path, root = sys.argv[1], sys.argv[2].rstrip("/") + "/"
lines = []
with tarfile.open(path, "r|gz") as tf:
    for m in tf:
        if not m.isfile():
            continue
        if not m.name.startswith(root):
            sys.exit(f"member outside {root}: {m.name}")
        h = hashlib.sha256()
        f = tf.extractfile(m)
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
        lines.append((m.name[len(root):], h.hexdigest()))
for rel, digest in sorted(lines, key=lambda x: x[0].encode()):
    print(f"{digest}  ./{rel}")
