# Thesis in the UNSW EE&T template (v2.00)

Build: `build.bat`, or `pdflatex thesis.tex` twice so the contents, pointers and
cross-references settle. Output: `thesis.pdf`.

- `latexdefs.tex` - the school's template definitions (12 pt Times, A4,
  2.54 cm margins, 1.5 spacing, UNSW red headings), plus the packages this
  thesis needs. The template's `units` package is replaced by `siunitx`.
- `summary.tex` - thesis summary sheet and pointers page (page numbers fill in
  automatically). Check it against the current form on Moodle, then sign.
- `cover.tex` (+ `abstract_body.tex`), `acknowledgements.tex`, `abbreviations.tex`
- `fr_*.tex` - the chapters. The main body (Chapter 1 to Chapter 11) is about
  93 pages, inside the template's 100-page limit.
- `figs/` - the figures. Data plots are all MATLAB: `fig_bits.pdf` and
  `fig_kr_sweep.pdf` from `figsrc_matlab/thesis_figs.m`; the Chapter 5 and 7
  figures (`fig_input_report.png`, `fig_stage1.pdf`, `fig_cr_bars.pdf`,
  `fig_residual.pdf`, `fig_cr_frames.pdf`, `fig_timing.pdf`, `fig_resources.pdf`)
  from `figsrc_matlab/thesis_figs_results.m`, which redraws the poster data
  without titles. The older PNGs in `figs/` are the poster versions and are not
  used. Block diagrams are TikZ in the chapter files.
- `\lpcDecCycles`, `\lpcDecTime` and `\lpcDecLat` in `latexdefs.tex` hold the
  measured LPC decoder figures (Table 7.7); `\tbc` no longer marks anything.
- `build.bat` compiles the thesis with MiKTeX (two pdflatex passes).
