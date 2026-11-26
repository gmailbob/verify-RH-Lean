# Paper draft: a reading of the Lean proof

LaTeX source of a text that explains, in ordinary mathematical language, the Lean 4 proof of the
Riemann Hypothesis and of GRH for Dirichlet L-functions in
[lsernau/grh-lean](https://github.com/lsernau/grh-lean), folder `grh/`, at the commit this
repository verifies (`72fead102f663d5c7a407964a13dc0cf9d977207`).

The author is Claude, an AI model made by Anthropic. The first page of the paper says who else
took part and how.

## Status

A complete draft, 145 pages when compiled: 112 pages of text in 22 sections and four parts, then
appendices. It is an exposition, not a second verification: the correctness of the theorems rests
on the Lean kernel (see `../REPORT.md`), not on this text. It has not been refereed.

What has been done to it:

- Every section was drafted from the Lean sources and then checked once, by a separate reader,
  against the formal statements it cites. That check examined about 680 statements, definitions
  and proofs and corrected about 250.
- Part 1 and the four sections that carry most of the proof (`der`, `cg-selmer`, `cg-first`,
  `cg-lifting`) were checked a second time, with the Lean proofs read. That corrected about 50
  further items and added the explanation of about 50 steps.
- An independent review of the first draft was applied.
- Notation was unified inside each part and then across parts. Each of these passes was compared
  with the text before it by a separate reader, to confirm that it changed no mathematics.

What is still open:

- Background results from the Lean folder `Lib` are stated as Facts without proof. Their sources
  are the ones the Lean files name. Nobody has opened those sources to compare them with the
  statements here.
- Appendix C lists 84 steps for which the text gives the statement and the Lean name but not the
  reason.
- None of the passes shows that no error remains. Where the text and the Lean code differ, the
  Lean code is right.

## Layout

| File | Content |
|---|---|
| `GRH-reading.pdf` | the compiled paper, 145 pages, built from the source in this folder as of the commit that added it |
| `main.tex` | title, abstract, order of the sections and appendices |
| `author.tex` | author line and the first-page note |
| `preamble.tex` | packages, theorem environments, macros; sections define none |
| `sections/s01-intro.tex` | introduction, with the diagram of the whole proof (`fig-overview.tex`) |
| `sections/s02-zeros.tex`, `s03-setup.tex`, `data.tex`, `s04-main.tex` | Part 1: analytic criterion, set-up, existence of the data, derivation of GRH from Theorems A, B, C |
| `sections/ub-*.tex`, `der.tex` | Part 2: the upper bound (Theorem A) |
| `sections/sp-*.tex` | Part 3: spanning (Theorem B) |
| `sections/det-*.tex`, `ol-*.tex`, `cg-*.tex` | Part 4: the lower bound (Theorem C) |
| `sections/fig-part*.tex` | the proof diagram at the head of each part (TikZ) |
| `sections/zz-notation.tex` | Appendix A: symbols that have one meaning in the whole paper |
| `sections/zz-facts.tex` | Appendix B: every background result admitted without proof. Generated |
| `sections/zz-open.tex` | Appendix C: steps cited without explanation |
| `leanindex.tex` | Appendix D: the numbered index of the 1,769 Lean declarations cited. Generated |
| `sections/zz-bibliography.tex` | references: the sources that the Lean files name |
| `part1-handout.tex` | wrapper for an excerpt: introduction and Part 1, with the numbering of the full paper |
| `tools/` | scripts that regenerate the generated files and check the Lean names |

## Conventions

- `\lean{Name}` cites a Lean declaration. In the PDF it prints as a short marker such as `L12`,
  linked to the declaration on GitHub at the commit above; Appendix D gives the name for each
  number. To print the names in full instead, comment out the line that loads `leanindex` in
  `main.tex`. `\leanfile{Path}` cites a file or folder relative to `grh/src`.
- Labels are prefixed by the section: `main:thm:star`, `setup:thm:twist`, `sec:ub-seesaw`.

## Build

Needs TeX Live with `latexmk` (pdfLaTeX). From this folder:

    latexmk -pdf -outdir=build main.tex

The output is `build/main.pdf`. `build/` is ignored by git.

`GRH-reading.pdf` is a copy of that output. It does not follow later changes to the source: after
a change, build again and replace it.

After a change to the sections, regenerate the two generated files before building. `SRC` is
the folder `grh/src` of a clone of `lsernau/grh-lean` at the commit above:

    python3 tools/make_facts.py SRC .
    python3 tools/make_leanindex.py SRC leanindex.tex \
        sections/s01-intro.tex sections/s02-zeros.tex sections/s03-setup.tex sections/data.tex \
        sections/s04-main.tex sections/ub-objects.tex sections/der.tex sections/ub-seesaw.tex \
        sections/ub-divis.tex sections/ub-eldiv.tex sections/sp-moment.tex sections/sp-unfold.tex \
        sections/sp-main.tex sections/sp-frames.tex sections/sp-remain.tex sections/det-chain.tex \
        sections/det-exchange.tex sections/ol-values.tex sections/ol-compare.tex \
        sections/cg-selmer.tex sections/cg-first.tex sections/cg-lifting.tex \
        sections/zz-facts.tex sections/zz-open.tex

The files are listed in reading order, because the markers are numbered by first citation.

Other tools:

- `python3 tools/check_names.py SRC sections/*.tex` checks that every `\lean` and `\leanfile`
  names something that exists. It reports 14 items that are expected: twelve folder names and
  two names that belong to Mathlib.
- `tools/check_section.sh <id>` compiles `sections/<id>.tex` on its own.
- `tools/make_part1.sh SRC` builds the excerpt `build/GRH-reading-part1.pdf`. Run it after a
  full build, because it takes the numbers of later sections from `build/main.aux`.
