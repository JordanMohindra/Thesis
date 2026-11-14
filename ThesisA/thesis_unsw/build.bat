@echo off
REM build.bat - compile thesis.tex to thesis.pdf with MiKTeX (double-click or run from a terminal).
REM Runs pdflatex twice so the contents, cross-references and the page numbers
REM on the summary sheet's Pointers page are filled in. No BibTeX step is needed
REM (the bibliography is written out in fr_biblio.tex).
setlocal
cd /d "%~dp0"
set PDFLATEX=pdflatex
where pdflatex >nul 2>&1 || set PDFLATEX="%LOCALAPPDATA%\Programs\MiKTeX\miktex\bin\x64\pdflatex.exe"
echo Pass 1 of 2...
%PDFLATEX% -interaction=nonstopmode -halt-on-error thesis.tex >nul
if errorlevel 1 goto fail
echo Pass 2 of 2...
%PDFLATEX% -interaction=nonstopmode -halt-on-error thesis.tex >nul
if errorlevel 1 goto fail
echo.
echo Done: thesis.pdf
endlocal
pause
exit /b 0
:fail
echo.
echo LaTeX stopped with an error. The end of thesis.log says why:
powershell -NoProfile -Command "Get-Content thesis.log -Tail 25"
endlocal
pause
exit /b 1
