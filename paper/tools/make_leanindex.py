#!/usr/bin/env python3
"""Number the Lean declarations cited in the paper, in order of first appearance.

Writes a LaTeX file of entries
    \\leanentry{Full.Name}{number}{path/of/file}{line}
for every name in \\lean{...} or \\leanref{...} that is a declaration of the project. With these
entries loaded, the alternative definition of \\lean prints a short marker "L<number>" that links
to the declaration on GitHub at the pinned commit, and an index of all markers can be printed.

Usage: make_leanindex.py SRC OUT.tex file.tex [file.tex ...]   (files in reading order)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_names  # noqa: E402

TEX_RE = re.compile(r'\\(?:lean|leanref)\{([^{}]*)\}')


def main():
    src, out = sys.argv[1], sys.argv[2]
    index, _ = check_names.build_index(src)
    seen, entries = set(), []
    for tex in sys.argv[3:]:
        with open(tex, encoding='utf-8') as f:
            text = f.read()
        for m in TEX_RE.finditer(text):
            name = m.group(1).strip()
            if name in seen or name not in index:
                continue
            seen.add(name)
            rel, line = index[name]
            entries.append((name, len(entries) + 1, rel[:-5], line))
    with open(out, 'w', encoding='utf-8') as f:
        for name, n, path, line in entries:
            f.write(f'\\leanentry{{{name}}}{{{n}}}{{{path}}}{{{line}}}\n')
    print(f'{len(entries)} declarations numbered -> {out}')


if __name__ == '__main__':
    main()
