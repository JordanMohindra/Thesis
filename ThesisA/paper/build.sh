#!/bin/bash
cd /mnt/user-data/outputs/thesis
cp thesis_report.tex _t.tex
if ! grep -q '\\end{document}' _t.tex; then echo '\end{document}' >> _t.tex; fi
pdflatex -interaction=nonstopmode _t.tex >/dev/null 2>&1
pdflatex -interaction=nonstopmode _t.tex >/dev/null 2>&1
E=$(grep -c "^! " _t.log)
echo "errors: $E"
if [ "$E" != "0" ]; then grep -n -A3 "^! " _t.log | head -40; fi
pdfinfo _t.pdf 2>/dev/null | grep Pages
