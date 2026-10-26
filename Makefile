SHELL := /bin/sh

OMNIBUS_TEX := number-theory.tex
ALLY_TEX := ally.tex
OMNIBUS_JOB := $(basename $(notdir $(OMNIBUS_TEX)))
VOLUME_JOB_PREFIX := number-theory-volume-
BUILDDIR := build

# Font configuration is owned by setup/fonts.tex, not by the Makefile.

ENGINE ?= lualatex
LATEXMK ?= latexmk
BIBER ?= biber
PYTHON ?= python3
OPEN ?= open

ARCHIVE ?= $(OMNIBUS_JOB)-source.zip
ARCHIVE_REF ?= HEAD
MAX_VOLUME_SWEEPS ?= 5
MAKEFILE_SELF := $(firstword $(MAKEFILE_LIST))

LATEXFLAGS := \
	-interaction=nonstopmode \
	-halt-on-error \
	-file-line-error \
	-recorder \
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

.DEFAULT_GOAL := __default
.NOTPARALLEL:

# GNU Make sees `make quick volume 2` as three goals.  They all share
# this dispatcher, which interprets the complete request exactly once.
PRIVATE_GOALS := __omnibus __volume_set __all __archive __doctor \
	__website __clean __distclean __help
PUBLIC_GOALS := $(filter-out $(PRIVATE_GOALS),$(MAKECMDGOALS))

.PHONY: __default __dispatch $(PRIVATE_GOALS) $(PUBLIC_GOALS)

ifneq ($(strip $(PUBLIC_GOALS)),)
$(PUBLIC_GOALS): __dispatch ; @:
endif

__default:
	@$(MAKE) --no-print-directory __omnibus \
		MODE=full PROFILE=canonical SUFFIX= FRESH=0

__dispatch:
	@set -eu; \
	mode=full; profile=canonical; scope=omnibus; scope_set=0; volume_number=; \
	fresh=0; open_after=0; \
	set_scope() { \
		if [ "$$scope_set" -eq 1 ] && [ "$$scope" != "$$1" ]; then \
			echo "Conflicting build actions: $$scope and $$1" >&2; exit 2; \
		fi; \
		scope="$$1"; scope_set=1; \
	}; \
	for word in $(MAKECMDGOALS); do \
		case "$$word" in \
			quick) mode=quick ;; \
			fresh) fresh=1 ;; \
			ally) profile=ally ;; \
			pdf|omnibus) set_scope omnibus ;; \
			volume) set_scope volume ;; \
			volumes) set_scope volumes ;; \
			all) set_scope all ;; \
			archive) set_scope archive ;; \
			website) set_scope website ;; \
			doctor) set_scope doctor ;; \
			clean) set_scope clean ;; \
			distclean) set_scope distclean ;; \
			help) set_scope help ;; \
			open) open_after=1 ;; \
			*) case "$$word" in \
				''|*[!0-9]*) echo "Unknown make word: $$word" >&2; \
					echo "Run 'make help' for valid combinations." >&2; exit 2 ;; \
				*) if [ -n "$$volume_number" ] && \
					[ "$$volume_number" != "$$word" ]; then \
						echo "Choose exactly one volume number." >&2; exit 2; \
					fi; volume_number="$$word" ;; \
			esac ;; \
		esac; \
	done; \
	case "$$scope" in \
		volume) \
			if [ -z "$$volume_number" ] || [ "$$volume_number" -eq 0 ]; then \
				echo "Usage: make [quick] volume N" >&2; exit 2; \
			fi ;; \
		*) if [ -n "$$volume_number" ]; then \
			echo "A volume number is only valid after 'volume'." >&2; exit 2; \
		   fi ;; \
	esac; \
	case "$$scope" in archive|doctor|website|clean|distclean|help) \
		if [ "$$mode" != full ] || [ "$$fresh" -eq 1 ] || \
		   [ "$$profile" != canonical ] || [ "$$open_after" -eq 1 ]; then \
			echo "$$scope does not combine with quick, fresh, ally, or open." >&2; exit 2; \
		fi ;; \
	esac; \
	suffix=; \
	if [ "$$profile" = ally ]; then suffix=-ally; fi; \
	case "$$scope" in \
		omnibus) target=__omnibus ;; \
		volume) target=__volume_set ;; \
		volumes) target=__volume_set; volume_number=all ;; \
		all) target=__all ;; \
		archive) target=__archive ;; \
		website) target=__website ;; \
		doctor) target=__doctor ;; \
		clean) target=__clean ;; \
		distclean) target=__distclean ;; \
		help) target=__help ;; \
	esac; \
	$(MAKE) --no-print-directory "$$target" MODE="$$mode" FRESH="$$fresh" \
		PROFILE="$$profile" SUFFIX="$$suffix" SELECT="$$volume_number" \
		OPEN_AFTER="$$open_after"

__omnibus:
	@set -eu; \
	source="$(OMNIBUS_TEX)"; \
	job="$(OMNIBUS_JOB)$(SUFFIX)"; \
	if [ "$(PROFILE)" = ally ]; then source="$(ALLY_TEX)"; fi; \
	if [ ! -f "$$source" ]; then \
		echo "Missing main file: $$source" >&2; exit 2; \
	fi; \
	mkdir -p "$(BUILDDIR)"; \
	if [ "$(FRESH)" = 1 ]; then \
		echo "==> Resetting generated state: $$job"; \
		rm -f "$(BUILDDIR)/$$job".*; \
	fi; \
	context="$(BUILDDIR)/$$job.build-context"; \
	full_stamp="$(BUILDDIR)/$$job.full-stamp"; \
	build_context() { \
		printf '%s\n' "date=$$(date +%Y-%m-%d)" \
			"engine=$(ENGINE)" "latexmk=$(LATEXMK)" \
			"latexflags=$(LATEXFLAGS)" "latexmkflags=$(LATEXMKFLAGS)" \
			"profile=$(PROFILE)" "suffix=$(SUFFIX)"; \
	}; \
	if [ "$(MODE)" = quick ]; then \
		echo "==> Quick build: $$job.pdf"; \
		NT_PDF_PROFILE="$(PROFILE)" \
			$(ENGINE) $(LATEXFLAGS) -jobname="$$job" "$$source"; \
		rm -f "$$full_stamp"; \
	else \
		force=; \
		if [ ! -f "$$full_stamp" ] || ! build_context | cmp -s - "$$context"; then \
			force=-gt; \
		fi; \
		echo "==> Full build: $$job.pdf"; \
		NT_PDF_PROFILE="$(PROFILE)" \
			$(LATEXMK) $(LATEXMKFLAGS) $$force -jobname="$$job" "$$source"; \
		build_context > "$$context"; \
		touch "$$full_stamp"; \
	fi; \
	cmp -s "$(BUILDDIR)/$$job.pdf" "$$job.pdf" || \
		cp -f "$(BUILDDIR)/$$job.pdf" "$$job.pdf"; \
	echo "==> Built $$job.pdf"; \
	if [ "$(OPEN_AFTER)" = 1 ]; then $(OPEN) "$$job.pdf"; fi

# External zref references create a cycle between volume auxiliaries.  Seed
# missing files with one pass, then let latexmk settle each stale volume.
# A quick (single-pass) build is deliberately NEVER marked fully settled.
__volume_set:
	@set -eu; \
	suffix="$(SUFFIX)"; \
	if [ "$(SELECT)" = all ]; then \
		max=; \
		for tex in volume-[0-9]*.tex; do \
			[ -e "$$tex" ] || continue; \
			n=$${tex#volume-}; n=$${n%.tex}; \
			case "$$n" in ''|*[!0-9]*) continue ;; esac; \
			if [ -z "$$max" ] || [ "$$n" -gt "$$max" ]; then max="$$n"; fi; \
		done; \
		if [ -z "$$max" ]; then echo "No volume-N.tex drivers found." >&2; exit 2; fi; \
	else max="$(SELECT)"; fi; \
	case "$$max" in ''|*[!0-9]*) echo "Invalid volume number: $$max" >&2; exit 2 ;; esac; \
	if [ "$$max" -eq 0 ]; then echo "Volume numbers begin at 1." >&2; exit 2; fi; \
	n=1; numbers=; \
	while [ "$$n" -le "$$max" ]; do \
		if [ ! -f "volume-$$n.tex" ]; then \
			echo "Missing predecessor driver: volume-$$n.tex" >&2; exit 2; \
		fi; \
		numbers="$$numbers $$n"; n=$$((n + 1)); \
	done; \
	mkdir -p "$(BUILDDIR)"; \
	if [ "$(FRESH)" = 1 ]; then \
		if [ "$(SELECT)" = all ]; then fresh_numbers="$$numbers"; \
		else fresh_numbers="$(SELECT)"; fi; \
		for n in $$fresh_numbers; do \
			job="$(VOLUME_JOB_PREFIX)$$n$$suffix"; \
			echo "==> Resetting generated state: $$job"; \
			rm -f "$(BUILDDIR)/$$job".*; \
		done; \
	fi; \
	external_aux_signature() { \
		for dep_tex in volume-[0-9]*.tex; do \
			[ -e "$$dep_tex" ] || continue; \
			dep_n=$${dep_tex#volume-}; dep_n=$${dep_n%.tex}; \
			case "$$dep_n" in ''|*[!0-9]*) continue ;; esac; \
			dep_aux="$(BUILDDIR)/$(VOLUME_JOB_PREFIX)$$dep_n$$suffix.aux"; \
			[ -f "$$dep_aux" ] && cksum "$$dep_aux"; \
		done | cksum | awk '{ print $$1 ":" $$2 }'; \
	}; \
	build_context() { \
		printf '%s\n' "date=$$(date +%Y-%m-%d)" \
			"engine=$(ENGINE)" "latexmk=$(LATEXMK)" \
			"latexflags=$(LATEXFLAGS)" "latexmkflags=$(LATEXMKFLAGS)" \
			"profile=$(PROFILE)" "suffix=$(SUFFIX)"; \
	}; \
	needs_rebuild() { \
		check_job="$$1"; check_mode="$${2-full}"; \
		check_stamp="$(BUILDDIR)/$$check_job.$$check_mode-stamp"; \
		check_fls="$(BUILDDIR)/$$check_job.fls"; \
		check_external="$(BUILDDIR)/$$check_job.external-aux.sig"; \
		check_context="$(BUILDDIR)/$$check_job.build-context"; \
		stale_reason=; \
		for required in \
			"$(BUILDDIR)/$$check_job.pdf" \
			"$(BUILDDIR)/$$check_job.aux" \
			"$$check_fls" \
			"$$check_external" \
			"$$check_stamp"; do \
			if [ ! -f "$$required" ]; then \
				stale_reason="missing $$required"; return 0; \
			fi; \
		done; \
		if [ "$$check_mode" = full ]; then \
			for required in "$(BUILDDIR)/$$check_job.fdb_latexmk" \
				"$(BUILDDIR)/$$check_job.bbl"; do \
				if [ ! -f "$$required" ]; then \
					stale_reason="missing $$required"; return 0; \
				fi; \
			done; \
		fi; \
		if ! build_context | cmp -s - "$$check_context"; then \
			stale_reason="build settings or date changed"; return 0; \
		fi; \
		if [ -f .latexmkrc ] && [ .latexmkrc -nt "$$check_stamp" ]; then \
			stale_reason=".latexmkrc changed"; return 0; \
		fi; \
		if [ -f scripts/latexmk-ci.rc ] && \
			[ scripts/latexmk-ci.rc -nt "$$check_stamp" ]; then \
			stale_reason="CI latexmk settings changed"; return 0; \
		fi; \
		if [ "$(MAKEFILE_SELF)" -nt "$$check_stamp" ]; then \
			stale_reason="$(MAKEFILE_SELF) changed"; return 0; \
		fi; \
		current_external=$$(external_aux_signature); \
		saved_external=$$(sed -n '1p' "$$check_external"); \
		if [ "$$current_external" != "$$saved_external" ]; then \
			stale_reason="cross-volume auxiliary data changed"; return 0; \
		fi; \
		while IFS= read -r record; do \
			case "$$record" in \
				INPUT\ *) \
					input=$${record#INPUT }; \
					case "$$input" in \
						*"$(VOLUME_JOB_PREFIX)"[0-9]*.aux) continue ;; \
					esac; \
					if [ ! -e "$$input" ]; then \
						stale_reason="recorded input disappeared: $$input"; return 0; \
					fi; \
					if [ "$$input" -nt "$$check_stamp" ]; then \
						stale_reason="newer input: $$input"; return 0; \
					fi ;; \
			esac; \
		done < "$$check_fls"; \
		return 1; \
	}; \
	build_one() { \
		n="$$1"; \
		tex="volume-$$n.tex"; job="$(VOLUME_JOB_PREFIX)$$n$$suffix"; \
		full_stamp="$(BUILDDIR)/$$job.full-stamp"; \
		quick_stamp="$(BUILDDIR)/$$job.quick-stamp"; \
		context="$(BUILDDIR)/$$job.build-context"; \
		external="$(BUILDDIR)/$$job.external-aux.sig"; \
		if [ "$(MODE)" = quick ]; then \
			if needs_rebuild "$$job" quick; then \
				echo "==> Quick build: $$job.pdf ($$stale_reason)"; \
				NT_PDF_PROFILE="$(PROFILE)" \
					NT_VOLUME_SUFFIX="$$suffix" \
					$(ENGINE) $(LATEXFLAGS) -jobname="$$job" "$$tex"; \
				external_aux_signature > "$$external"; \
				build_context > "$$context"; \
				touch "$$quick_stamp"; \
				rm -f "$$full_stamp"; \
			else \
				echo "==> Up to date: $$job.pdf"; \
			fi; \
		else \
			if needs_rebuild "$$job" full; then \
				echo "==> Full build: $$job.pdf ($$stale_reason)"; \
				NT_PDF_PROFILE="$(PROFILE)" \
					NT_VOLUME_SUFFIX="$$suffix" \
					$(LATEXMK) $(LATEXMKFLAGS) -gt \
					-jobname="$$job" "$$tex"; \
				external_aux_signature > "$$external"; \
				build_context > "$$context"; \
				touch "$$full_stamp" "$$quick_stamp"; \
			else \
				echo "==> Up to date: $$job.pdf"; \
			fi; \
		fi; \
		cmp -s "$(BUILDDIR)/$$job.pdf" "$$job.pdf" || \
			cp -f "$(BUILDDIR)/$$job.pdf" "$$job.pdf"; \
	}; \
	build_sweep() { \
		for n in $$numbers; do build_one "$$n"; done; \
	}; \
	bootstrap_sweep() { \
		echo "==> Bootstrapping auxiliary files for all volumes"; \
		for n in $$numbers; do \
			tex="volume-$$n.tex"; job="$(VOLUME_JOB_PREFIX)$$n$$suffix"; \
			if [ -f "$(BUILDDIR)/$$job.aux" ]; then continue; fi; \
			echo "==> Bootstrap pass: $$job.pdf"; \
			NT_PDF_PROFILE="$(PROFILE)" \
				NT_VOLUME_SUFFIX="$$suffix" \
				$(ENGINE) $(LATEXFLAGS) -jobname="$$job" "$$tex"; \
		done; \
	}; \
	volume_signature() { \
		for n in $$numbers; do \
			aux="$(BUILDDIR)/$(VOLUME_JOB_PREFIX)$$n$$suffix.aux"; \
			if [ -f "$$aux" ]; then \
				cksum "$$aux"; \
			else \
				printf 'MISSING %s\n' "$$aux"; \
			fi; \
		done | cksum | awk '{ print $$1 ":" $$2 }'; \
	}; \
	if [ "$(MODE)" = quick ]; then \
		build_sweep; \
	else \
		bootstrap=0; \
		for n in $$numbers; do \
			aux="$(BUILDDIR)/$(VOLUME_JOB_PREFIX)$$n$$suffix.aux"; \
			if [ ! -f "$$aux" ]; then bootstrap=1; break; fi; \
		done; \
		if [ "$$bootstrap" -eq 1 ]; then bootstrap_sweep; fi; \
		previous=$$(volume_signature); \
		stable=0; sweep=1; \
		while [ "$$sweep" -le "$(MAX_VOLUME_SWEEPS)" ]; do \
			echo "==> Volume sweep $$sweep/$(MAX_VOLUME_SWEEPS)"; \
			build_sweep; \
			signature=$$(volume_signature); \
			all_current=1; \
			for n in $$numbers; do \
				job="$(VOLUME_JOB_PREFIX)$$n$$suffix"; \
				if needs_rebuild "$$job" full; then all_current=0; break; fi; \
			done; \
			if [ "$$all_current" -eq 1 ] && [ "$$signature" = "$$previous" ]; then \
				stable=1; break; \
			fi; \
			previous="$$signature"; sweep=$$((sweep + 1)); \
		done; \
		if [ "$$stable" -ne 1 ]; then \
			echo "Volume auxiliaries did not stabilize after $(MAX_VOLUME_SWEEPS) sweeps." >&2; \
			echo "Inspect the logs before raising MAX_VOLUME_SWEEPS." >&2; exit 2; \
		fi; \
	fi; \
	echo "==> Built volumes 1--$$max ($(MODE))"; \
	if [ "$(OPEN_AFTER)" = 1 ]; then \
		$(OPEN) "$(VOLUME_JOB_PREFIX)$$max$$suffix.pdf"; \
	fi

__all:
	@$(MAKE) --no-print-directory __omnibus MODE="$(MODE)" FRESH="$(FRESH)" \
		PROFILE="$(PROFILE)" SUFFIX="$(SUFFIX)" OPEN_AFTER=0
	@$(MAKE) --no-print-directory __volume_set MODE="$(MODE)" FRESH="$(FRESH)" \
		PROFILE="$(PROFILE)" SUFFIX="$(SUFFIX)" SELECT=all \
		OPEN_AFTER="$(OPEN_AFTER)"

# Prepare the book landing page using existing canonical and Ally PDFs.
# No TeX compilation, Jekyll rendering, or GitHub publication occurs.
# The generator also copies PDFs and creates cover images so all links work
# when the generated site source is rendered locally.
__website:
	@set -eu; \
	mkdir -p "$(BUILDDIR)"; \
	work=$$(mktemp -d "$(BUILDDIR)/.website.XXXXXXXX"); \
	trap 'rm -rf "$$work"' EXIT HUP INT TERM; \
	mkdir -p "$$work/pdfs"; \
	copy_pdf() { \
		file="$$1"; \
		if [ ! -f "$$file" ]; then \
			echo "Missing $$file. Build the canonical and Ally PDFs first." >&2; exit 2; \
		fi; \
		ln "$$file" "$$work/pdfs/$$file" 2>/dev/null || \
			cp "$$file" "$$work/pdfs/$$file"; \
	}; \
	copy_pdf "$(OMNIBUS_JOB).pdf"; \
	copy_pdf "$(OMNIBUS_JOB)-ally.pdf"; \
	for tex in volume-[0-9]*.tex; do \
		[ -f "$$tex" ] || continue; \
		n=$${tex#volume-}; n=$${n%.tex}; \
		case "$$n" in ''|*[!0-9]*) continue ;; esac; \
		copy_pdf "$(VOLUME_JOB_PREFIX)$$n.pdf"; \
		copy_pdf "$(VOLUME_JOB_PREFIX)$$n-ally.pdf"; \
	done; \
	$(PYTHON) scripts/book-publication.py site \
		--pdf-dir "$$work/pdfs" --output "$$work/site"; \
	rm -rf "$(BUILDDIR)/website"; \
	mv "$$work/site" "$(BUILDDIR)/website"; \
	echo "==> Landing-page source: $(BUILDDIR)/website/notes/number-theory/index.md"; \
	echo "==> Supporting files: $(BUILDDIR)/website/notes/number-theory/"

__archive:
	@set -eu; \
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		echo "make archive must run inside a Git repository." >&2; exit 2; \
	fi; \
	if ! git rev-parse --verify "$(ARCHIVE_REF)^{commit}" >/dev/null 2>&1; then \
		echo "Unknown archive ref: $(ARCHIVE_REF)" >&2; exit 2; \
	fi; \
	tmp="$(ARCHIVE).tmp"; \
	trap 'rm -f "'"'"'$$tmp'"'"'"' EXIT HUP INT TERM; \
	rm -f "$$tmp"; \
	git archive --format=zip --output="$$tmp" "$(ARCHIVE_REF)"; \
	mv -f "$$tmp" "$(ARCHIVE)"; \
	trap - EXIT HUP INT TERM; \
	echo "==> Archived tracked files from $(ARCHIVE_REF) to $(ARCHIVE)"

__doctor:
	@set -eu; status=0; \
	for tool in "$(ENGINE)" "$(LATEXMK)" "$(BIBER)" git; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			echo "Missing command: $$tool" >&2; status=1; \
		fi; \
	done; \
	if [ ! -f "$(OMNIBUS_TEX)" ]; then \
		echo "Missing main file: $(OMNIBUS_TEX)" >&2; status=1; \
	fi; \
	if [ ! -f "$(ALLY_TEX)" ]; then \
		echo "Missing Ally master file: $(ALLY_TEX)" >&2; status=1; \
	fi; \
	if [ ! -f "setup/document-metadata.tex" ]; then \
		echo "Missing shared metadata file: setup/document-metadata.tex" >&2; status=1; \
	fi; \
	if [ ! -f setup/fonts.tex ]; then \
		echo "Missing font configuration: setup/fonts.tex" >&2; status=1; \
	fi; \
	max=0; \
	for tex in volume-[0-9]*.tex; do \
		[ -e "$$tex" ] || continue; n=$${tex#volume-}; n=$${n%.tex}; \
		case "$$n" in ''|*[!0-9]*) continue ;; esac; \
		[ "$$n" -le "$$max" ] || max="$$n"; \
	done; \
	n=1; while [ "$$n" -le "$$max" ]; do \
		if [ ! -f "volume-$$n.tex" ]; then \
			echo "Missing volume driver: volume-$$n.tex" >&2; status=1; \
		fi; n=$$((n + 1)); \
	done; \
	if [ "$$status" -eq 0 ]; then \
		echo "==> Build setup looks good ($$max volume drivers)"; \
	fi; exit "$$status"

__clean:
	@echo "==> Cleaning $(BUILDDIR)/"
	@rm -rf "$(BUILDDIR)"

__distclean: __clean
	@echo "==> Removing generated PDFs and the default source archive"
	@rm -f "$(OMNIBUS_JOB).pdf" "$(OMNIBUS_JOB)-"*.pdf \
		"$(VOLUME_JOB_PREFIX)"[0-9]*.pdf \
		"$(VOLUME_JOB_PREFIX)"[0-9]*-*.pdf \
		volume-[0-9]*.pdf volume-[0-9]*-*.pdf "$(ARCHIVE)"

__help:
	@printf '%s\n' \
		'make                              full omnibus (Libertinus)' \
		'make quick                        one-pass omnibus update' \
		'make fresh                        discard omnibus build state; full rebuild' \
		'make quick fresh                  discard omnibus build state; one fresh pass' \
		'make ally                         Ally-compatible omnibus PDF' \
		'make quick ally                   one-pass Ally-compatible update' \
		'make volume N                     build volumes 1--N' \
		'make quick volume N               one pass for each volume 1--N' \
		'make fresh volume N               reset volume N state; rebuild volumes 1--N' \
		'make quick fresh volume N         reset volume N state; one pass over 1--N' \
		'make ally volume N                Ally-compatible volumes 1--N' \
		'make volumes                      all discovered volumes; stabilize links' \
		'make quick volumes                one pass over all discovered volumes' \
		'make fresh volumes                reset and rebuild all discovered volumes' \
		'make ally volumes                 all Ally-compatible volumes' \
		'make all                          omnibus plus all volumes' \
		'make ally all                     Ally omnibus plus all Ally volumes' \
		'make archive                      zip tracked files at ARCHIVE_REF (HEAD)' \
		'make website                      generate landing page from existing PDFs (no TeX)' \
		'make open [volume N|volumes]      build, then open the result' \
		'make doctor                       check tools, font setup, and volume sequence' \
		'make clean                        remove transient build files' \
		'make distclean                    also remove generated PDFs/archive' \
		'' \
		'Variables: ARCHIVE=<file>, ARCHIVE_REF=<commit>,' \
		'           MAX_VOLUME_SWEEPS=<n>, ENGINE=<cmd>, LATEXMK=<cmd>,' \
		'           PYTHON=<cmd>.'
