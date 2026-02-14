TEXFILE := elementary-number-theory.tex
BIBFILE := references.bib
ENGINE  := lualatex
BIBTOOL := biber
BUILDDIR := build

BASE := $(basename $(TEXFILE))
ROOTPDF := $(BASE).pdf
BUILDPDF := $(BUILDDIR)/$(BASE).pdf

# Flags: Note the output-directory is set here
LATEXFLAGS := -interaction=nonstopmode -halt-on-error -synctex=1 -output-directory=$(BUILDDIR)

.PHONY: all pdf clean distclean open bib

all: pdf

$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

pdf: $(ROOTPDF)

$(ROOTPDF): $(TEXFILE) $(BIBFILE) | $(BUILDDIR)
	@echo "==> 1) $(ENGINE) (Pass 1)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)

	@echo "==> 2) $(BIBTOOL)"
	@$(BIBTOOL) --input-directory $(BUILDDIR) --output-directory $(BUILDDIR) $(BUILDDIR)/$(BASE) \
		|| { echo "Biber failed. Check $(BUILDDIR)/$(BASE).blg"; exit 1; }

	@echo "==> 3) $(ENGINE) (Pass 2)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)

	@echo "==> 4) $(ENGINE) (Pass 3)"
	@$(ENGINE) $(LATEXFLAGS) $(TEXFILE)

	@cp -f $(BUILDPDF) $(ROOTPDF)
	@echo "==> Built $(ROOTPDF)"

clean:
	@echo "==> Cleaning $(BUILDDIR)/"
	@rm -rf $(BUILDDIR)

distclean: clean
	@rm -f $(ROOTPDF)
