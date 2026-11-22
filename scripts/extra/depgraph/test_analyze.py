"""Test depgraph_analyze against brute force on random graphs.

Usage: python3 -I test_analyze.py <path-to-depgraph_analyze> [trials]

Each trial writes a random graph in depgraph's file format (some with cycles, duplicate
edges and unreachable nodes), runs the analyzer with --dump, and checks every immediate
dominator and every cone size against a brute-force computation:
  d dominates v  <=>  v is unreachable from the root once d is removed;
  idom(v) = the strict dominator of v with the most dominators itself.
Also runs the normal report on each graph to check it completes.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

exe = sys.argv[1]
trials = int(sys.argv[2]) if len(sys.argv) > 2 else 300
maxn = int(sys.argv[3]) if len(sys.argv) > 3 else 40


def write_graph(d, n, edges, users, mods):
    with open(os.path.join(d, "nodes.tsv"), "w") as f:
        for i in range(n):
            f.write(f"{i}\tn{i}\t{'t' if i % 3 else 'd'}\t{mods[i]}\t{users[i]}\n")
    with open(os.path.join(d, "edges.bin"), "wb") as f:
        f.write(b"DGR1" + struct.pack("<I", n))
        for i in range(n):
            ts = edges[i]
            f.write(struct.pack("<I", len(ts)) + b"".join(struct.pack("<I", t) for t in ts))


def reach(n, edges, root, removed=None):
    seen = {root} if root != removed else set()
    stack = [root] if root != removed else []
    while stack:
        v = stack.pop()
        for w in edges[v]:
            if w != removed and w not in seen:
                seen.add(w)
                stack.append(w)
    return seen


def brute(n, edges, root):
    R = reach(n, edges, root)
    doms = {v: {v, root} for v in R}
    for d in R:
        if d == root:
            continue
        without = reach(n, edges, root, removed=d)
        for v in R:
            if v != d and v not in without:
                doms[v].add(d)
    idom = {}
    for v in R:
        if v == root:
            idom[v] = root
            continue
        strict = doms[v] - {v}
        idom[v] = max(strict, key=lambda d: len(doms[d]))
    cones = {v: len(reach(n, edges, v)) for v in R}
    return idom, cones


rng = random.Random(20261121)
failures = 0
for t in range(trials):
    n = rng.randint(1, maxn)
    p = rng.choice([0.05, 0.1, 0.2, 0.35])
    dag_only = rng.random() < 0.5
    edges = []
    for i in range(n):
        ts = []
        for j in range(n):
            if i == j:
                continue
            if dag_only and j < i:      # DAG: edges only to higher indices
                continue
            if rng.random() < p:
                ts.append(j)
        if ts and rng.random() < 0.2:    # duplicate an edge: the analyzer must cope
            ts.append(ts[0])
        edges.append(ts)
    users = [rng.randint(0, 1) for _ in range(n)]
    mods = [rng.choice(["Development.A", "Formalism.B", "Lemmata", "Main", "Mathlib.X"]) for _ in range(n)]
    root = 0
    with tempfile.TemporaryDirectory() as d:
        write_graph(d, n, edges, users, mods)
        out = subprocess.run([exe, d, "n0", "--dump"], capture_output=True, text=True)
        if out.returncode != 0:
            print("analyzer failed:", out.stderr); failures += 1; continue
        got_idom, got_cone = {}, {}
        for line in out.stdout.splitlines():
            kind, a, b = line.split()
            if kind == "idom":
                got_idom[int(a[1:])] = int(b[1:])
            else:
                got_cone[int(a[1:])] = int(b)
        exp_idom, exp_cone = brute(n, edges, root)
        if got_idom != exp_idom or got_cone != exp_cone:
            failures += 1
            print(f"trial {t}: MISMATCH n={n} edges={edges}")
            print("  expected idom", exp_idom, "\n  got     ", got_idom)
        rep = subprocess.run([exe, d, "n0", "--query", "n0", "--query", f"n{n-1}", "--min-pct", "0"],
                             capture_output=True, text=True)
        if rep.returncode != 0 or "dominator tree" not in rep.stdout:
            failures += 1
            print(f"trial {t}: report mode failed: {rep.stderr}")

print(f"{trials} random graphs: {trials - failures} passed, {failures} failed")
sys.exit(1 if failures else 0)
