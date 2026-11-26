#!/usr/bin/env python3
"""Check that every Lean name cited in the paper exists in the Lean sources.

Builds an index of fully qualified declaration names by tracking `namespace` / `section` / `end`
in each file, then looks up every \\lean{...} and \\leanref{...} of the given .tex files, and checks
that every \\leanfile{...} is a file. The index is textual: it knows theorems, definitions,
structures with their fields, classes, inductives and named instances, but not names that Lean
generates. A name that is not in the project (a Mathlib name, say) is reported as "not in project".

Usage: check_names.py SRC file.tex [file.tex ...]
"""
import os
import re
import sys
from collections import defaultdict

DECL_RE = re.compile(
    r'^(?:@\[[^\]]*\]\s*)*(?:(?:private|protected|noncomputable|scoped|local|nonrec|unsafe|partial)\s+)*'
    r'(theorem|lemma|def|abbrev|structure|class|inductive|instance|irreducible_def|opaque|alias)\s+'
    r'([^\s:({\[]+)')
FIELD_RE = re.compile(r"^\s+([^\W\d][\w'!?]*)\s*(?:[({\[:]|$)")
CTOR_RE = re.compile(r"^\s+\|\s*([^\W\d][\w'!?]*)")
SCOPE_RE = re.compile(r'^(?:noncomputable\s+|public\s+)*(namespace|section|mutual)\b\s*(\S*)')
END_RE = re.compile(r'^end\b\s*(\S*)')
TEX_RE = re.compile(r'\\(lean|leanref|leanfile)\{([^{}]*)\}')


def strip_comments(text):
    out, i, n, depth = [], 0, len(text), 0
    while i < n:
        if text.startswith('/-', i):
            depth += 1
            i += 2
        elif depth and text.startswith('-/', i):
            depth -= 1
            i += 2
        elif depth:
            if text[i] == '\n':
                out.append('\n')
            i += 1
        elif text.startswith('--', i):
            while i < n and text[i] != '\n':
                i += 1
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def build_index(src):
    index = {}                     # full name -> (file, line)
    by_last = defaultdict(set)     # last component -> full names
    for root, _, names in os.walk(src):
        for name in names:
            if not name.endswith('.lean'):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, src)
            with open(path, encoding='utf-8') as f:
                lines = strip_comments(f.read()).split('\n')
            stack = []             # (kind, name)
            owner = None           # structure/class/inductive whose body we are in
            for ln, line in enumerate(lines, 1):
                if line and line[0] not in ' \t':
                    owner = None
                    m = SCOPE_RE.match(line)
                    if m:
                        stack.append((m.group(1), m.group(2)))
                        continue
                    m = END_RE.match(line)
                    if m:
                        if stack:
                            stack.pop()
                        continue
                    m = DECL_RE.match(line)
                    if m and re.match(r'[^\W\d]|«', m.group(2)):
                        ns = '.'.join(n for k, n in stack if k == 'namespace' and n)
                        written = m.group(2)
                        if written.startswith('_root_.'):
                            full = written[len('_root_.'):]
                        else:
                            full = (ns + '.' if ns else '') + written
                        index.setdefault(full, (rel, ln))
                        by_last[full.split('.')[-1]].add(full)
                        if m.group(1) in ('structure', 'class', 'inductive'):
                            owner = full
                elif owner:
                    m = FIELD_RE.match(line) or CTOR_RE.match(line)
                    if m:
                        full = owner + '.' + m.group(1)
                        index.setdefault(full, (rel, ln))
                        by_last[m.group(1)].add(full)
    return index, by_last


def main():
    src = sys.argv[1]
    index, by_last = build_index(src)
    total = bad = 0
    for tex in sys.argv[2:]:
        with open(tex, encoding='utf-8') as f:
            text = f.read()
        problems = []
        seen = set()
        for m in TEX_RE.finditer(text):
            kind, arg = m.group(1), m.group(2).strip()
            if (kind, arg) in seen:
                continue
            seen.add((kind, arg))
            total += 1
            line = text.count('\n', 0, m.start()) + 1
            if kind == 'leanfile':
                if not os.path.isfile(os.path.join(src, arg + '.lean')):
                    problems.append(f'  L{line}: file not found: {arg}')
                continue
            if arg in index:
                continue
            last = arg.split('.')[-1]
            cands = sorted(by_last.get(last, ()))
            if cands:
                problems.append(f'  L{line}: {arg}: no exact match; candidates: ' + ', '.join(cands[:4]))
            else:
                problems.append(f'  L{line}: {arg}: not in project')
        bad += len(problems)
        print(f'{os.path.basename(tex)}: {len(seen)} references, {len(problems)} to check')
        for p in problems:
            print(p)
    print(f'TOTAL: {total} references, {bad} to check')


if __name__ == '__main__':
    main()
