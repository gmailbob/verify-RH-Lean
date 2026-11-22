"""Lexical audit of a Lean project tree. Reads files as text; executes nothing.

Usage: python3 -I scan_source.py <project-dir> <json-out>

Reports:
  A. Hard-fail tokens: anything that can make Lean accept a proof without the
     kernel checking it, or that adds trusted code. Any hit in code fails the scan.
  B. Metaprogramming inventory: user-defined commands/tactics/macros, direct
     metavariable assignment, environment modification. Needs a human read.
  C. Options: every set_option key, plus the lakefile's options.
  D. Import graph: modules reachable from the final theorems.
  E. The statement files, printed in full.

Exit status 1 if section A has hits in code, else 0.
"""
import json
import multiprocessing
import os
import re
import sys
from collections import Counter, defaultdict, deque

proj, json_out = sys.argv[1], sys.argv[2]
src = os.path.join(proj, "src")
FINAL_MODULES = ["Main", "Statements"]

# --------------------------------------------------------------------------- A
HARD = {
    "sorry": "unfinished proof (sorryAx)",
    "admit": "synonym for sorry",
    "sorryAx": "the sorry axiom itself",
    "axiom": "declares a new axiom",
    "unsafe": "unsafe definitions bypass kernel checks",
    "native_decide": "trusts compiled code (Lean.ofReduceBool)",
    "ofReduceBool": "trusts compiled code",
    "ofReduceNat": "trusts compiled code",
    "trustCompiler": "trusts compiled code",
    "implemented_by": "replaces code with untrusted implementation",
    "extern": "foreign implementation",
    "opaque": "opaque constant (can hide unsafe implementations)",
    "skipKernelTC": "debug.skipKernelTC disables the kernel",
    "debug": "debug.* options (e.g. debug.skipKernelTC)",
    "Kernel.Environment": "direct kernel environment access",
    "addDeclWithoutChecking": "adds declarations unchecked",
    "replay": "environment replay hooks",
}

# --------------------------------------------------------------------------- B
META = {
    "run_cmd": r"\brun_cmd\b",
    "run_elab": r"\brun_elab\b",
    "run_meta": r"\brun_meta\b",
    "run_tac": r"\brun_tac\b",
    "by_elab": r"\bby_elab\b",
    "#eval": r"#eval\b",
    "inline Lean.Elab/Lean.Meta": r"\bLean\.(?:Elab|Meta)\.",
    "initialize": r"\b(?:builtin_)?initialize\b",
    "elab definition": r"^[ \t]*(?:@\[[^\]]*\]\s*)?(?:local\s+|scoped\s+)?(?:elab|elab_rules)\b",
    "macro definition": r"^[ \t]*(?:@\[[^\]]*\]\s*)?(?:local\s+|scoped\s+)?(?:macro|macro_rules)\b",
    "syntax definition": r"^[ \t]*(?:@\[[^\]]*\]\s*)?(?:local\s+|scoped\s+)?syntax\b",
    "elaborator attribute": r"@\[\s*(?:command_elab|term_elab|tactic|macro)\b",
    "addDecl": r"\baddDecl\b",
    "modifyEnv / setEnv": r"\b(?:modifyEnv|setEnv)\b",
    "direct mvar assign": r"\.assign\b|\bassignExprMVar\b",
    "Kernel.isDefEq / whnf": r"\bKernel\.(?:isDefEq|whnf)\b",
    "IO / process": r"\bIO\.(?:Process|FS)\b|\bSystem\.FilePath\b",
    "partial def": r"\bpartial\s+def\b",
    "allowUnsafeReducibility": r"\ballowUnsafeReducibility\b",
    "maxHeartbeats 0": r"set_option\s+maxHeartbeats\s+0\b",
}

IDENT_CH = r"A-Za-z0-9_'!?₀-₉ₐ-ₜᵢ-ᵪ"
hard_re = {t: re.compile(rf"(?<![{IDENT_CH}]){re.escape(t)}(?![{IDENT_CH}])") for t in HARD}
meta_re = {k: re.compile(v, re.M) for k, v in META.items()}
opt_re = re.compile(r"\bset_option\s+([A-Za-z_][A-Za-z0-9_.]*)\s+(\S+)")
elab_name_re = re.compile(r'^[ \t]*(?:@\[[^\]]*\]\s*)?(?:local\s+|scoped\s+)?(?:elab|macro|syntax)(?::\w+)?\s+(?:\([^)]*\)\s*)?"([^"]+)"', re.M)
import_re = re.compile(r"^(?:public\s+|private\s+)?(?:meta\s+)?import\s+(?:all\s+)?([^\s]+)")


TOKEN_RE = re.compile(r'/-|-/|--[^\n]*|"(?:\\.|[^"\\\n])*"', re.S)


def _blank(seg):
    return re.sub(r"[^\n]", " ", seg)


def strip_comments(text):
    """Blank out comments (nested /- -/ and --) and string literal contents,
    keeping offsets and line structure. Regex-driven so it is fast."""
    out, pos, depth, block_start = [], 0, 0, 0
    for m in TOKEN_RE.finditer(text):
        tok = m.group()
        if depth:
            if tok == "/-":
                depth += 1
            elif tok == "-/":
                depth -= 1
                if depth == 0:
                    out.append(_blank(text[block_start:m.end()]))
                    pos = m.end()
            continue
        if tok == "/-":
            out.append(text[pos:m.start()])
            depth, block_start = 1, m.start()
        elif tok == "-/":
            continue                       # stray closer outside a comment
        elif tok.startswith("--"):
            out.append(text[pos:m.start()] + _blank(tok))
            pos = m.end()
        else:                              # string literal
            out.append(text[pos:m.start()] + '"' + _blank(tok[1:-1]) + '"')
            pos = m.end()
    out.append(_blank(text[block_start:]) if depth else text[pos:])
    return "".join(out)


def header_imports(code):
    mods = []
    for line in code.splitlines():
        s = line.strip()
        if not s or s in ("module", "prelude"):
            continue
        m = import_re.match(s)
        if not m:
            break
        mods.append(m.group(1))
    return mods


def scan_file(args):
    p, mod = args
    raw = open(p, "rb").read().decode("utf-8", errors="replace")
    code = strip_comments(raw)
    raw_lines, code_lines = raw.splitlines(), code.splitlines()
    hard, meta, opts, defs = [], [], Counter(), []
    for t, r in hard_re.items():
        if r.search(raw):
            for ln, line in enumerate(raw_lines, 1):
                if r.search(line):
                    in_code = ln <= len(code_lines) and bool(r.search(code_lines[ln - 1]))
                    hard.append((t, mod, ln, in_code, line.strip()[:160]))
    for k, r in meta_re.items():
        for m in r.finditer(code):
            ln = code.count("\n", 0, m.start()) + 1
            meta.append((k, mod, ln, raw_lines[ln - 1].strip()[:160]))
    for m in opt_re.finditer(code):
        opts[m.group(1)] += 1
    for m in elab_name_re.finditer(raw):   # raw: string literals are blanked in `code`
        defs.append(m.group(1).strip())
    return mod, header_imports(code), hard, meta, opts, defs


def count_uses(args):
    p, pattern = args
    code = strip_comments(open(p, "rb").read().decode("utf-8", errors="replace"))
    return Counter(m.group() for m in re.finditer(pattern, code))


hard_hits = defaultdict(list)        # token -> [(module, line, in_code, text)]
meta_hits = defaultdict(list)        # kind  -> [(module, line, text)]
opt_keys = Counter()
custom_syntax = {}                   # quoted keyword -> first defining module
syntax_defs = Counter()              # quoted keyword -> number of definitions
imports = {}
non_lean = []
jobs = []
for root, dirs, files in os.walk(src):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(root, f)
        rel = os.path.relpath(p, src)
        if f.endswith(".lean"):
            jobs.append((p, rel[:-5].replace(os.sep, ".")))
        else:
            non_lean.append(rel)

with multiprocessing.Pool() as pool:
    for mod, imps, hard, meta, opts, defs in pool.imap_unordered(scan_file, jobs, chunksize=256):
        imports[mod] = imps
        for t, *rest in hard:
            hard_hits[t].append(tuple(rest))
        for k, *rest in meta:
            meta_hits[k].append(tuple(rest))
        opt_keys.update(opts)
        for kw in defs:
            custom_syntax.setdefault(kw, mod)
            syntax_defs[kw] += 1
    for v in list(hard_hits.values()) + list(meta_hits.values()):
        v.sort()

    # usage counts of every user-defined keyword (second pass, one combined regex)
    syntax_uses = Counter({kw: 0 for kw in custom_syntax})
    if custom_syntax:
        alts = "|".join(re.escape(k) for k in sorted(custom_syntax, key=len, reverse=True))
        pattern = rf"(?<![{IDENT_CH}])(?:{alts})(?![{IDENT_CH}])"
        for c in pool.imap_unordered(count_uses, [(p, pattern) for p, _ in jobs], chunksize=256):
            syntax_uses.update(c)

# --------------------------------------------------------------------------- D
seen, q, external = set(), deque(FINAL_MODULES), Counter()
while q:
    m = q.popleft()
    if m in seen:
        continue
    seen.add(m)
    if m in imports:
        q.extend(imports[m])
    else:
        external[m.split(".")[0]] += 1
cone = {m for m in seen if m in imports}
outside = sorted(set(imports) - cone)

# --------------------------------------------------------------------------- report
def section(t):
    print("\n" + "=" * 78 + "\n" + t + "\n" + "=" * 78)

print(f"project: {proj}\n.lean files: {len(imports)}   other files under src/: {len(non_lean)}")
for x in non_lean[:20]:
    print("   non-.lean:", x)

section("A. HARD-FAIL TOKENS (any hit in code fails)")
code_fail = 0
for t, why in HARD.items():
    hits = hard_hits.get(t, [])
    nc = sum(1 for h in hits if h[2])
    code_fail += nc
    print(f"  {t:24s} in code: {nc:5d}   in comments/strings: {len(hits) - nc:5d}   ({why})")
for t, hits in hard_hits.items():
    for mod, ln, in_code, line in hits[:30]:
        print(f"    {'CODE' if in_code else 'cmt '} {t}: {mod}:{ln}: {line}")

section("B. METAPROGRAMMING INVENTORY (review each)")
for k in META:
    hits = meta_hits.get(k, [])
    files = len({h[0] for h in hits})
    print(f"  {k:26s} {len(hits):6d} hits in {files} files")
print("\n  User-defined syntax keywords and how often each is used:")
for kw, mod in sorted(custom_syntax.items(), key=lambda kv: -syntax_uses[kv[0]]):
    print(f"    {kw!r:30s} uses {syntax_uses[kw]:6d}   defined {syntax_defs[kw]}x, first in {mod}")
for k in ["run_cmd", "run_elab", "run_meta", "run_tac", "by_elab", "#eval", "initialize",
          "inline Lean.Elab/Lean.Meta", "elab definition",
          "elaborator attribute", "addDecl", "modifyEnv / setEnv", "direct mvar assign",
          "Kernel.isDefEq / whnf", "IO / process", "partial def"]:
    hits = meta_hits.get(k, [])
    if hits:
        print(f"\n  -- {k} --")
        for mod, ln, line in hits[:40]:
            print(f"    {mod}:{ln}: {line}")

section("C. OPTIONS")
print("  set_option keys used in source:")
for k, n in opt_keys.most_common():
    print(f"    {n:7d}  {k}")
lf = os.path.join(proj, "lakefile.toml")
if os.path.exists(lf):
    print("\n  lakefile.toml (full):")
    for line in open(lf, encoding="utf-8"):
        print("    | " + line.rstrip())
for other in ("lakefile.lean",):
    if os.path.exists(os.path.join(proj, other)):
        print(f"\n  WARNING: {other} present: it is Lean code executed by lake; review it")

section("D. IMPORT GRAPH")
print(f"  modules reachable from {FINAL_MODULES}: {len(cone)} of {len(imports)} project modules")
print(f"  external import roots: {dict(external.most_common())}")
print(f"  project modules NOT reachable (built by lake but irrelevant to the final theorems): {len(outside)}")
for m in outside[:20]:
    print("    ", m)
for k in ["run_cmd", "run_tac", "elab definition", "addDecl", "direct mvar assign"]:
    fs = {h[0] for h in meta_hits.get(k, [])}
    print(f"  files with '{k}' inside the cone: {len(fs & cone)} / {len(fs)}")

section("E. STATEMENT FILES (read these)")
for m in FINAL_MODULES:
    p = os.path.join(src, m + ".lean")
    print(f"\n  ---- {m}.lean ----")
    for line in open(p, encoding="utf-8"):
        print("    | " + line.rstrip())

summary = {
    "lean_files": len(imports),
    "non_lean_files": non_lean,
    "hard_fail_hits_in_code": code_fail,
    "hard_tokens": {t: {"code": sum(1 for h in hard_hits.get(t, []) if h[2]),
                        "comment": sum(1 for h in hard_hits.get(t, []) if not h[2])} for t in HARD},
    "meta_counts": {k: len(meta_hits.get(k, [])) for k in META},
    "custom_syntax_uses": syntax_uses,
    "set_option_keys": dict(opt_keys),
    "cone_size": len(cone),
    "outside_cone": len(outside),
    "external_roots": dict(external),
}
with open(json_out, "w") as fh:
    json.dump(summary, fh, indent=1, sort_keys=True)

section("RESULT")
print(f"  hard-fail hits in code: {code_fail}  ->  {'FAIL' if code_fail else 'PASS'}")
print("  Section B items are not failures; the kernel re-checks everything they produce,")
print("  but read them to understand how the proof was assembled.")
sys.exit(1 if code_fail else 0)
