TEXFILE := number-theory.tex
BUILDDIR := build

OUTPUT_PREFIX := $(basename $(notdir $(TEXFILE)))
DEFAULTPDF := $(OUTPUT_PREFIX).pdf

DEFAULT_FONT := libertinus
FONTDIR := fontsetups

ENGINE ?= lualatex
LATEXMK ?= latexmk
BIBER ?= biber
OPEN ?= open

.DEFAULT_GOAL := pdf

.NOTPARALLEL:

LATEXFLAGS := \
	-interaction=nonstopmode \
	-halt-on-error \
	-file-line-error \
	-synctex=1 \
	-output-directory=$(BUILDDIR)

LATEXMKFLAGS := \
	-lualatex \
	-bibtex \
	-interaction=nonstopmode \
	-halt-on-error \
	-file-line-error \
	-synctex=1 \
	-outdir=$(BUILDDIR)

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

fontsetup = $(FONTDIR)/$(1)-custom-kerning.tex

ROOTPDFS := $(addprefix $(OUTPUT_PREFIX)-,$(addsuffix .pdf,$(FONTS)))

.PHONY: all pdf quick fonts font clean distclean open doctor help $(FONTS)

pdf: | $(BUILDDIR)
	@setup="$(call fontsetup,$(DEFAULT_FONT))"; \
	if [ ! -f "$$setup" ]; then \
		echo "Missing font setup: $$setup" >&2; \
		exit 2; \
	fi; \
	echo "==> Building $(DEFAULTPDF)"; \
	echo "==> Font setup: $$setup"; \
	NT_FONT_SETUP="$$setup" \
		$(LATEXMK) $(LATEXMKFLAGS) -jobname="$(OUTPUT_PREFIX)" "$(TEXFILE)"; \
	cmp -s "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)" \
		|| cp -f "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)"; \
	echo "==> Built $(DEFAULTPDF)"

quick: | $(BUILDDIR)
	@setup="$(call fontsetup,$(DEFAULT_FONT))"; \
	if [ ! -f "$$setup" ]; then \
		echo "Missing font setup: $$setup" >&2; \
		exit 2; \
	fi; \
	echo "==> Quick build of $(DEFAULTPDF)"; \
	echo "==> Font setup: $$setup"; \
	NT_FONT_SETUP="$$setup" \
		$(ENGINE) $(LATEXFLAGS) -jobname="$(OUTPUT_PREFIX)" "$(TEXFILE)"; \
	cmp -s "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)" \
		|| cp -f "$(BUILDDIR)/$(OUTPUT_PREFIX).pdf" "$(DEFAULTPDF)"; \
	echo "==> Built $(DEFAULTPDF) (quick)"

# Generic entry point, e.g. `make font FONT=stix-two`.
font: | $(BUILDDIR)
	@if [ -z "$(FONT)" ]; then \
		echo "Usage: make font FONT=<name>" >&2; \
		echo "Available fonts: $(FONTS)" >&2; \
		exit 2; \
	fi
	@case " $(FONTS) " in \
		*" $(FONT) "*) ;; \
		*) echo "Unknown font: $(FONT)" >&2; \
		   echo "Available fonts: $(FONTS)" >&2; \
		   exit 2 ;; \
	esac
	@setup="$(call fontsetup,$(FONT))"; \
	output="$(OUTPUT_PREFIX)-$(FONT)"; \
	if [ ! -f "$$setup" ]; then \
		echo "Missing font setup: $$setup" >&2; \
		exit 2; \
	fi; \
	echo "==> Building $$output.pdf"; \
	echo "==> Font setup: $$setup"; \
	NT_FONT_SETUP="$$setup" \
		$(LATEXMK) $(LATEXMKFLAGS) -jobname="$$output" "$(TEXFILE)"; \
	cmp -s "$(BUILDDIR)/$$output.pdf" "$$output.pdf" \
		|| cp -f "$(BUILDDIR)/$$output.pdf" "$$output.pdf"; \
	echo "==> Built $$output.pdf"

$(FONTS):
	@$(MAKE) --no-print-directory font FONT="$@"

fonts:
	@set -e; \
	for font in $(FONTS); do \
		$(MAKE) --no-print-directory font FONT="$$font"; \
	done

all: pdf fonts

$(BUILDDIR):
	@mkdir -p "$(BUILDDIR)"

open: pdf
	@$(OPEN) "$(DEFAULTPDF)"

doctor:
	@status=0; \
	for tool in "$(ENGINE)" "$(LATEXMK)" "$(BIBER)"; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			echo "Missing command: $$tool" >&2; \
			status=1; \
		fi; \
	done; \
	if [ ! -f "$(TEXFILE)" ]; then \
		echo "Missing main file: $(TEXFILE)" >&2; \
		status=1; \
	fi; \
	for font in $(FONTS); do \
		setup="$(FONTDIR)/$$font-custom-kerning.tex"; \
		if [ ! -f "$$setup" ]; then \
			echo "Missing font setup: $$setup" >&2; \
			status=1; \
		fi; \
	done; \
	if [ "$$status" -eq 0 ]; then \
		echo "==> Build setup looks good"; \
	fi; \
	exit "$$status"

clean:
	@echo "==> Cleaning $(BUILDDIR)/"
	@rm -rf "$(BUILDDIR)"

distclean: clean
	@echo "==> Removing generated PDFs"
	@rm -f "$(DEFAULTPDF)" $(ROOTPDFS)

help:
	@printf '%s\n' \
		'make / make pdf            full default-font build' \
		'make quick                 one LuaLaTeX pass only' \
		'make <font>                build one font comparison' \
		'make font FONT=<font>      same, with an explicit font name' \
		'make fonts                 build all font comparisons serially' \
		'make all                   build the normal PDF and all fonts' \
		'make open                  build and open the normal PDF' \
		'make doctor                check tools and font setup files' \
		'make clean                 remove transient build files' \
		'make distclean             remove build files and generated PDFs'
