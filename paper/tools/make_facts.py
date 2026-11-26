#!/usr/bin/env python3
"""Generate Appendix A: the background results that the paper admits.

Part 1 of the appendix lists every `fact` environment of the sections. Part 2 lists, section by
section, every other declaration of the Lean folder `Lib` that the text cites outside a `fact`
environment, so that the two lists together are complete: they contain every `Lib` declaration
the paper cites.

Usage: make_facts.py SRC PAPER_DIR   (writes PAPER_DIR/sections/zz-facts.tex)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_names  # noqa: E402

ORDER = ['s01-intro', 's02-zeros', 's03-setup', 'data', 's04-main', 'ub-objects', 'der',
         'ub-seesaw', 'ub-divis', 'ub-eldiv', 'sp-moment', 'sp-unfold', 'sp-main', 'sp-frames',
         'sp-remain', 'det-chain', 'det-exchange', 'ol-values', 'ol-compare', 'cg-selmer',
         'cg-first', 'cg-lifting']
LABEL = {'s01-intro': 'intro', 's02-zeros': 'zeros', 's03-setup': 'setup', 's04-main': 'main'}
NAME_RE = re.compile(r'\\(?:lean|leanref)\{([^{}]*)\}')


def bracket_arg(text, pos):
    depth, i = 0, pos + 1
    while i < len(text):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        elif c == ']' and depth == 0:
            return text[pos + 1:i], i + 1
        i += 1
    return '', pos


def fact_blocks(tex):
    """Yield (label, title without Lean names, names in the whole environment, start, end)."""
    for m in re.finditer(r'\\begin\{fact\}', tex):
        end = tex.find(r'\end{fact}', m.end())
        if end < 0:
            continue
        pos, title = m.end(), ''
        if pos < len(tex) and tex[pos] == '[':
            title, pos = bracket_arg(tex, pos)
        lab = re.search(r'\\label\{([^}]*)\}', tex[pos:end])
        plain = re.sub(r'\\lean(?:file|ref)?\{[^}]*\}', '', title)
        plain = re.sub(r'\s*[;,]\s*(?=[;,]|$)', '', plain)
        plain = re.sub(r'^[;,\s]+|[;,\s]+$', '', plain).strip()
        names = []
        for n in NAME_RE.findall(tex[m.start():end]):
            if n not in names:
                names.append(n)
        yield (lab.group(1) if lab else None, plain, names, m.start(), end)


def main():
    src, root = sys.argv[1], sys.argv[2]
    index, _ = check_names.build_index(src)
    out = [r'\section{Background results admitted}\label{sec:app-facts}',
           '',
           r'This appendix lists what the paper takes from the folder \texttt{Lib} of the Lean text,',
           r'the part classed there as known in the literature. The first list contains the results',
           r'that the text states as Facts, without proof. A few of them are proved in the folder',
           r'\texttt{New} but are known results; the text says so where it states them. The second',
           r'list contains every other declaration of \texttt{Lib} that the text cites, in the',
           r'course of a proof or of an explanation, without stating it as a Fact. Both lists are',
           r'generated from the source of the paper, so together they are complete. The statements',
           r'are those of the Lean text, which are often weaker than the theorems of the',
           r'literature; the paper has not compared them with their sources.',
           '', r'\subsection*{Results stated as Facts}', '',
           r'\begin{itemize}[leftmargin=2em,itemsep=1pt]']
    nfacts, other = 0, []
    for sid in ORDER:
        path = os.path.join(root, 'sections', sid + '.tex')
        if not os.path.isfile(path):
            continue
        with open(path, encoding='utf-8') as f:
            tex = f.read()
        in_fact = set()
        for lab, title, names, a, b in fact_blocks(tex):
            nfacts += 1
            in_fact.update(names)
            ref = f'Fact~\\ref{{{lab}}}' if lab else 'A fact'
            line = f'\\item {ref}, Section~\\ref{{sec:{LABEL.get(sid, sid)}}}.'
            if title:
                line += ' ' + title[0].upper() + title[1:] + '.'
            lib = [n for n in names if n in index and index[n][0].startswith('Lib/')]
            new = [n for n in names if n in index and index[n][0].startswith('New/')]
            if lib:
                line += ' ' + ', '.join(f'\\lean{{{n}}}' for n in lib) + '.'
            if new and not lib:
                line += ' Proved in \\texttt{New}: ' + ', '.join(f'\\lean{{{n}}}' for n in new) + '.'
            out.append(line)
        rest = []
        for n in NAME_RE.findall(tex):
            if n in in_fact or n in rest:
                continue
            if n in index and index[n][0].startswith('Lib/'):
                rest.append(n)
        if rest:
            other.append((sid, rest))
    out += [r'\end{itemize}', '',
            r'\subsection*{Other declarations of \texttt{Lib} cited in the text}', '',
            r'\begin{itemize}[leftmargin=2em,itemsep=1pt]']
    nother = 0
    for sid, rest in other:
        nother += len(rest)
        out.append(f'\\item Section~\\ref{{sec:{LABEL.get(sid, sid)}}}: '
                   + ', '.join(f'\\lean{{{n}}}' for n in rest) + '.')
    out += [r'\end{itemize}']
    with open(os.path.join(root, 'sections', 'zz-facts.tex'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(out) + '\n')
    print(f'{nfacts} facts; {nother} other Lib declarations cited in {len(other)} sections')


if __name__ == '__main__':
    main()
