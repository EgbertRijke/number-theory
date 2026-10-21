#!/usr/bin/env bash
# Rolling full TeX Live for GitHub-hosted Ubuntu x86_64 runners.
set -euo pipefail

case "${1:-}" in
  prepare)
    : "${RUNNER_TEMP:?}" "${GITHUB_OUTPUT:?}"
    work=$(mktemp -d "$RUNNER_TEMP/texlive-installer.XXXXXX")
    # Prefer CTAN's automatic mirror selection, with verified-HTTPS fallbacks.
    # Use the successful mirror for both installation and package updates.
    archive_url=
    downloaded=false
    for base in \
      https://mirrors.ctan.org/systems/texlive/tlnet \
      https://ctan.math.illinois.edu/systems/texlive/tlnet \
      https://mirror.math.princeton.edu/pub/CTAN/systems/texlive/tlnet; do
      echo "Trying TeX Live mirror: $base" >&2
      if archive_url=$(curl --fail --location --show-error --silent --retry 3 \
        --proto '=https' --proto-redir '=https' \
        --output "$work/installer.tar.gz" \
        --write-out '%{url_effective}' \
        "$base/install-tl-unx.tar.gz"); then
        downloaded=true
        break
      fi
    done
    [[ "$downloaded" == true ]] || {
      echo "Could not download the TeX Live installer from any HTTPS mirror" >&2
      exit 1
    }
    case "$archive_url" in
      https://*/install-tl-unx.tar.gz) repository=${archive_url%/install-tl-unx.tar.gz} ;;
      *) echo "Unexpected TeX Live installer URL" >&2; exit 1 ;;
    esac
    mkdir "$work/installer"
    tar -xzf "$work/installer.tar.gz" -C "$work/installer" --strip-components=1
    version=$(perl "$work/installer/install-tl" --version)
    year=$(printf '%s\n' "$version" | sed -nE 's/^TeX Live .*version ([0-9]{4}).*/\1/p')
    [[ "$year" =~ ^[0-9]{4}$ ]] || { echo "Cannot determine TeX Live release" >&2; exit 1; }
    {
      printf 'installer=%s\n' "$work/installer/install-tl"
      printf 'repository=%s\n' "$repository"
      printf 'year=%s\n' "$year"
      printf 'day=%s\n' "$(date -u +%F)"
    } >> "$GITHUB_OUTPUT"
    ;;
  install)
    : "${NT_TEXLIVE_ROOT:?}" "${NT_TEXLIVE_INSTALLER:?}" "${NT_TEXLIVE_REPOSITORY:?}"
    : "${NT_TEXLIVE_YEAR:?}" "${GITHUB_PATH:?}"
    mkdir -p diagnostics
    texbin="$NT_TEXLIVE_ROOT/bin/x86_64-linux"
    if [[ ! -x "$texbin/tlmgr" ]]; then
      profile=$(mktemp)
      cat > "$profile" <<PROFILE
selected_scheme scheme-full
TEXDIR $NT_TEXLIVE_ROOT
TEXMFLOCAL $NT_TEXLIVE_ROOT/texmf-local
TEXMFSYSVAR $NT_TEXLIVE_ROOT/texmf-var
TEXMFSYSCONFIG $NT_TEXLIVE_ROOT/texmf-config
TEXMFVAR $NT_TEXLIVE_ROOT/user-var
TEXMFCONFIG $NT_TEXLIVE_ROOT/user-config
TEXMFHOME $NT_TEXLIVE_ROOT/texmf-home
binary_x86_64-linux 1
instopt_adjustpath 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
tlpdbopt_autobackup 0
PROFILE
      perl "$NT_TEXLIVE_INSTALLER" --profile "$profile" \
        --repository "$NT_TEXLIVE_REPOSITORY" 2>&1 | tee diagnostics/texlive-install.log
      rm -f "$profile"
    fi
    export PATH="$texbin:$PATH"
    # Cache keys include the remote release year; never attempt a cross-year update.
    installed_year=$(tlmgr --version | sed -nE 's/^TeX Live .*version ([0-9]{4}).*/\1/p')
    [[ "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
      echo "Unexpected cached TeX Live release: $installed_year" >&2; exit 1;
    }
    tlmgr option repository "$NT_TEXLIVE_REPOSITORY"
    tlmgr option autobackup 0
    # Deliberately unconditional: an exact cache hit is NOT proof of freshness.
    # Any failed refresh stops the build instead of falling back to stale packages.
    tlmgr update --self 2>&1 | tee diagnostics/texlive-update-self.log
    tlmgr update --all 2>&1 | tee diagnostics/texlive-update-all.log
    fmtutil-sys --byfmt lualatex-dev 2>&1 | tee diagnostics/texlive-format.log
    luaotfload-tool --update 2>&1 | tee diagnostics/texlive-fonts.log
    printf '%s\n' "$texbin" >> "$GITHUB_PATH"
    {
      printf 'Repository: %s\n' "$NT_TEXLIVE_REPOSITORY"
      date -u
      tlmgr --version
      lualatex-dev --version
      latexmk --version
      biber --version
    } > diagnostics/toolchain.txt
    tlmgr info --only-installed > diagnostics/texlive-packages.txt
    # --version alone reports the engine, not the loaded LaTeX kernel.
    printf '%s\n' '\documentclass{article}' \
      '\begin{document}\typeout{CI-LATEX-FORMAT: \fmtversion}CI format check.\end{document}' \
      > diagnostics/format-check.tex
    lualatex-dev -interaction=nonstopmode -halt-on-error \
      -output-directory=diagnostics diagnostics/format-check.tex
    ;;
  *) echo "Usage: bash scripts/texlive-ci.sh prepare|install" >&2; exit 2 ;;
esac
