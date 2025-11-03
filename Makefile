# Makefile for building with lualatex + biber
# Usage:
#   make         -> build PDF (full sequence)
#   make draft   -> fast draft (one lualatex run, no biber)
#   make clean   -> remove aux files
#   make distclean-> remove aux files + pdf
#   make open    -> open produced PDF (macOS/Linux)
#
# Edit TEXFILE below if your main file has another name.

TEXFILE := ent-lua.tex
BIBFILE := references.bib            # optional; used for clarity
ENGINE  := lualatex
BIBTOOL := biber

# basename without extension (make builtin)
BASE := $(basename $(TEXFILE))
PDF  := $(BASE).pdf

LATEXFLAGS := -interaction=nonstopmode -halt-on-error -synctex=1

.PHONY: all pdf draft clean distclean open bib view

all: pdf

# Standard full build: lualatex -> biber -> lualatex -> lualatex
pdf: $(PDF)

$(PDF): $(TEXFILE) $(BIBFILE)
	@echo "==> 1) $(ENGINE) ($(TEXFILE))"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)
ifneq ("$(shell $(BIBTOOL) --version 2>/dev/null || true)","")
	@echo "==> 2) $(BIBTOOL) ($(BASE))"
	@$(BIBTOOL) $(BASE) || { echo "Biber failed"; exit 1; }
else
	@echo "==> 2) Skipping biber: $(BIBTOOL) not found on PATH"
endif
	@echo "==> 3) $(ENGINE) (pass 2)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)
	@echo "==> 4) $(ENGINE) (pass 3)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)
	@echo "==> Built $(PDF)"

# Faster draft target (no biber; single lualatex run)
draft: $(TEXFILE)
	@echo "==> Draft build (single $(ENGINE) run)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)
	@echo "==> Draft PDF: $(PDF)"

# Run only biber (useful when you changed bibliography only)
bib:
	@$(BIBTOOL) $(BASE)

# Convenience: open the produced PDF (macOS or Linux)
open: $(PDF)
	@echo "==> Opening $(PDF)"
	@{ if command -v open >/dev/null 2>&1; then open "$(PDF)"; \
	   elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$(PDF)"; \
	   else echo "No known 'open' command found (tried open and xdg-open)."; fi; }

# Remove common auxiliary files (keeps the pdf)
clean:
	@echo "==> Cleaning auxiliary files"
	@rm -f *.aux *.bbl *.bcf *.blg *.run.xml *.run.xml.* \
	       *.lof *.lot *.toc *.out *.fls *.fdb_latexmk *.synctex.gz \
	       *.nav *.snm *.vrb *.idx *.ind *.ilg

# Full clean: also remove pdf
distclean: clean
	@echo "==> Removing PDF and additional build artefacts"
	@rm -f $(PDF)

# optional: build using latexmk (if you have it); uncomment to use
# latexmk: 
# 	latexmk -pdf -pdflatex="lualatex $(LATEXFLAGS)" -use-make $(TEXFILE)

