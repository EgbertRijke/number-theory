TEXFILE := elementary-number-theory.tex
BIBFILE := references.bib
ENGINE  := lualatex
BIBTOOL := biber
BUILDDIR := build

BASE := $(basename $(TEXFILE))

OUTPUT_PREFIX := number-theory

DEFAULT_FONT := libertinus

.DEFAULT_GOAL := pdf

# Flags
LATEXFLAGS := -interaction=nonstopmode -halt-on-error -synctex=1 -file-line-error -output-directory=$(BUILDDIR)

# --------------------------------------------------------------------
# Font setup files
# --------------------------------------------------------------------

FONTDIR := fontsetups

FONTS := \
        alegreya \
	libertinus \
	stix-two \
	eb-garamond \
	schola \
	bonum \
	xcharter \
	erewhon \
	new-computer-modern \
	new-computer-modern-book \
	kpfonts \
        cochineal \
        etbb \
        baskervaldx \
        scholax \
        xits \
        cmu-concrete \
        cormorant-garamond \
        junicode \
        source-serif \
        oldstandard \
        fbb \
        gentium \
        charis-sil \
        noto-serif
#	termes \
#       pagella \
#       pagella-asana \
#       ibm-plex-serif \
#       cmu-concrete-euler \


FONTSETUP_alegreya                 := $(FONTDIR)/alegreya-custom-kerning.tex
FONTSETUP_libertinus               := $(FONTDIR)/libertinus-custom-kerning.tex
FONTSETUP_stix-two                 := $(FONTDIR)/stix-two-custom-kerning.tex
FONTSETUP_eb-garamond              := $(FONTDIR)/eb-garamond-custom-kerning.tex
FONTSETUP_schola                   := $(FONTDIR)/schola-custom-kerning.tex
FONTSETUP_bonum                    := $(FONTDIR)/bonum-custom-kerning.tex
FONTSETUP_xcharter                 := $(FONTDIR)/xcharter-custom-kerning.tex
FONTSETUP_erewhon                  := $(FONTDIR)/erewhon-custom-kerning.tex
FONTSETUP_new-computer-modern      := $(FONTDIR)/new-computer-modern-custom-kerning.tex
FONTSETUP_new-computer-modern-book := $(FONTDIR)/new-computer-modern-book-custom-kerning.tex
FONTSETUP_kpfonts                  := $(FONTDIR)/kpfonts-custom-kerning.tex
FONTSETUP_cochineal                := $(FONTDIR)/cochineal-custom-kerning.tex
FONTSETUP_etbb                     := $(FONTDIR)/etbb-custom-kerning.tex
FONTSETUP_baskervaldx              := $(FONTDIR)/baskervaldx-custom-kerning.tex
FONTSETUP_scholax                  := $(FONTDIR)/scholax-custom-kerning.tex
FONTSETUP_xits                     := $(FONTDIR)/xits-custom-kerning.tex
FONTSETUP_cmu-concrete             := $(FONTDIR)/cmu-concrete-custom-kerning.tex
FONTSETUP_cormorant-garamond       := $(FONTDIR)/cormorant-garamond-custom-kerning.tex
FONTSETUP_junicode                 := $(FONTDIR)/junicode-custom-kerning.tex
FONTSETUP_source-serif             := $(FONTDIR)/source-serif-custom-kerning.tex
FONTSETUP_oldstandard              := $(FONTDIR)/oldstandard-custom-kerning.tex
FONTSETUP_fbb                      := $(FONTDIR)/fbb-custom-kerning.tex
FONTSETUP_gentium                  := $(FONTDIR)/gentium-custom-kerning.tex
FONTSETUP_charis-sil               := $(FONTDIR)/charis-sil-custom-kerning.tex
FONTSETUP_noto-serif               := $(FONTDIR)/noto-serif-custom-kerning.tex
# FONTSETUP_termes                   := $(FONTDIR)/termes-custom-kerning.tex
# FONTSETUP_pagella                  := $(FONTDIR)/pagella-custom-kerning.tex
# FONTSETUP_pagella-asana            := $(FONTDIR)/pagella-asana-custom-kerning.tex
# FONTSETUP_ibm-plex-serif           := $(FONTDIR)/ibm-plex-serif-custom-kerning.tex
# FONTSETUP_cmu-concrete-euler       := $(FONTDIR)/cmu-concrete-euler-custom-kerning.tex

ROOTPDFS := $(addprefix $(OUTPUT_PREFIX)-,$(addsuffix .pdf,$(FONTS)))
DEFAULTPDF := $(OUTPUT_PREFIX).pdf

$(DEFAULTPDF): $(TEXFILE) $(BIBFILE) $(FONTSETUP_$(DEFAULT_FONT)) | $(BUILDDIR)
	@echo "==> Building $(DEFAULTPDF)"
	@echo "==> Font setup: $(FONTSETUP_$(DEFAULT_FONT))"

	@echo "==> 1) $(ENGINE) (Pass 1)"
	@NT_FONT_SETUP="$(FONTSETUP_$(DEFAULT_FONT))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)" $(TEXFILE)

	@echo "==> 2) $(BIBTOOL)"
	@$(BIBTOOL) \
		--input-directory $(BUILDDIR) \
		--output-directory $(BUILDDIR) \
		"$(OUTPUT_PREFIX)" \
		|| { echo "Biber failed. Check $(BUILDDIR)/$(OUTPUT_PREFIX).blg"; exit 1; }

	@echo "==> 3) $(ENGINE) (Pass 2)"
	@NT_FONT_SETUP="$(FONTSETUP_$(DEFAULT_FONT))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)" $(TEXFILE)

	@echo "==> 4) $(ENGINE) (Pass 3)"
	@NT_FONT_SETUP="$(FONTSETUP_$(DEFAULT_FONT))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)" $(TEXFILE)

	@cp -f "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)"
	@echo "==> Built $(DEFAULTPDF)"

.PHONY: all pdf quick fonts clean distclean open $(FONTS)

all: fonts

fonts: $(ROOTPDFS)

pdf: $(DEFAULTPDF)

quick: $(TEXFILE) $(FONTSETUP_$(DEFAULT_FONT)) | $(BUILDDIR)
	@echo "==> Quick build of $(DEFAULTPDF)"
	@echo "==> Font setup: $(FONTSETUP_$(DEFAULT_FONT))"
	@echo "==> $(ENGINE) (single pass)"
	@NT_FONT_SETUP="$(FONTSETUP_$(DEFAULT_FONT))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)" $(TEXFILE)
	@cp -f "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)"
	@echo "==> Built $(DEFAULTPDF) (quick)"

$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

# --------------------------------------------------------------------
# Template for building one font version
# --------------------------------------------------------------------

define FONT_template

$(1): $(OUTPUT_PREFIX)-$(1).pdf

$(OUTPUT_PREFIX)-$(1).pdf: $(TEXFILE) $(BIBFILE) $$(FONTSETUP_$(1)) | $(BUILDDIR)
	@echo "==> Building $(OUTPUT_PREFIX)-$(1).pdf"
	@echo "==> Font setup: $$(FONTSETUP_$(1))"

	@echo "==> 1) $(ENGINE) (Pass 1)"
	@NT_FONT_SETUP="$$(FONTSETUP_$(1))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)-$(1)" $(TEXFILE)

	@echo "==> 2) $(BIBTOOL)"
	@$(BIBTOOL) \
		--input-directory $(BUILDDIR) \
		--output-directory $(BUILDDIR) \
		"$(OUTPUT_PREFIX)-$(1)" \
		|| { echo "Biber failed. Check $(BUILDDIR)/$(OUTPUT_PREFIX)-$(1).blg"; exit 1; }

	@echo "==> 3) $(ENGINE) (Pass 2)"
	@NT_FONT_SETUP="$$(FONTSETUP_$(1))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)-$(1)" $(TEXFILE)

	@echo "==> 4) $(ENGINE) (Pass 3)"
	@NT_FONT_SETUP="$$(FONTSETUP_$(1))" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)-$(1)" $(TEXFILE)

	@cp -f "$(BUILDDIR)/$(OUTPUT_PREFIX)-$(1).pdf" "$(OUTPUT_PREFIX)-$(1).pdf"
	@echo "==> Built $(OUTPUT_PREFIX)-$(1).pdf"

endef

$(foreach font,$(FONTS),$(eval $(call FONT_template,$(font))))

open: $(DEFAULTPDF)
	@open $(DEFAULTPDF)

clean:
	@echo "==> Cleaning $(BUILDDIR)/"
	@rm -rf $(BUILDDIR)

distclean: clean
	@echo "==> Removing generated PDFs"
	@rm -f $(ROOTPDFS)
