# Thesis in the UNSW EE&T template (v2.00)

Build: `pdflatex thesis.tex` (run three times so the contents, pointers and
cross-references settle). Output: `thesis.pdf`.

- `latexdefs.tex` - the school's template definitions (12 pt Times, A4,
  2.54 cm margins, 1.5 spacing, UNSW red headings), plus the packages this
  thesis needs. The template's `units` package is replaced by `siunitx`.
- `summary.tex` - thesis summary sheet and pointers page (page numbers fill in
  automatically). Check it against the current form on Moodle, then sign.
- `cover.tex` (+ `abstract_body.tex`), `acknowledgements.tex`, `abbreviations.tex`
- `fr_*.tex` - the chapters. The main body (Chapter 1 to Chapter 11) is about
  88 pages, inside the template's 100-page limit.
- `figs/` - the figures. Data plots are all MATLAB: `fig_bits.pdf` and
  `fig_kr_sweep.pdf` from `figsrc_matlab/thesis_figs.m`, the PNGs from
  `../Matlab_Sim/make_poster_figs.m`. Block diagrams are TikZ in the chapter files.
- Orange values (`\tbc`, `\lpcDecTime` etc. in `latexdefs.tex`) are expected
  figures for the parallel LPC decoder, to be replaced by the board measurement.
