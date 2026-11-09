# Thesis in the UNSW EE&T template (v2.00)

Build: `pdflatex thesis.tex` (run three times so the contents, pointers and
cross-references settle). Output: `thesis.pdf`.

- `latexdefs.tex` - the school's template definitions (12 pt Times, A4,
  2.54 cm margins, 1.5 spacing, UNSW red headings), plus the packages this
  thesis needs. The template's `units` package is replaced by `siunitx`.
- `summary.tex` - thesis summary sheet and pointers page (page numbers fill in
  automatically). Check it against the current form on Moodle, then sign.
- `cover.tex` (+ `abstract_body.tex`), `acknowledgements.tex`, `abbreviations.tex`
- `fr_*.tex` - the chapters. The two long baseline-comparison chapters are
  Appendices A and B so the main body stays under the 100-page limit.
