#!/usr/bin/env bash
set -euo pipefail

release_repositories=(
  https://ctan.math.illinois.edu/systems/texlive/tlnet
  https://mirror.math.princeton.edu/pub/CTAN/systems/texlive/tlnet
  https://ftp.fau.de/ctan/systems/texlive/tlnet
)

cached_year() {
  local texbin="${NT_TEXLIVE_ROOT:-}/bin/x86_64-linux"
  [[ -x "$texbin/tlmgr" ]] || return 1
  "$texbin/tlmgr" --version 2>/dev/null |
    sed -nE 's/^TeX Live .*version ([0-9]{4}).*/\1/p'
}

case "${1:-}" in
  inspect-cache)
    : "${NT_TEXLIVE_ROOT:?}" "${GITHUB_OUTPUT:?}"
    matched="${NT_TEXLIVE_CACHE_MATCHED_KEY:-}"
    if installed_year=$(cached_year) && [[ "$installed_year" =~ ^[0-9]{4}$ ]]; then
      echo "::notice::Usable TeX Live $installed_year at $NT_TEXLIVE_ROOT (cache key: ${matched:-none})."
      printf 'usable=true\nyear=%s\n' "$installed_year" >> "$GITHUB_OUTPUT"
    elif [[ -n "$matched" ]]; then
      echo "::error::GitHub restored cache $matched, but $NT_TEXLIVE_ROOT/bin/x86_64-linux/tlmgr is missing or unusable. Refusing to reinstall over a restored cache." >&2
      exit 1
    else
      echo "::warning::No usable TeX Live cache restored; this runner will need a fresh installation."
      printf 'usable=false\nyear=\n' >> "$GITHUB_OUTPUT"
    fi
    ;;
  prepare)
    : "${RUNNER_TEMP:?}" "${GITHUB_OUTPUT:?}" "${NT_TEXLIVE_ROOT:?}" "${NT_TEXLIVE_YEAR:?}"
    if installed_year=$(cached_year) && [[ "$installed_year" =~ ^[0-9]{4}$ ]]; then
      [[ "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
        echo "::error::Cached TeX Live $installed_year does not match configured release $NT_TEXLIVE_YEAR." >&2
        exit 1
      }
      echo "::notice::Reusing cached TeX Live $installed_year; skipping installer download."
      {
        printf 'installer=\n'
        printf 'repository=%s\n' "${release_repositories[0]}"
        printf 'year=%s\n' "$installed_year"
        printf 'day=%s\n' "$(date -u +%F)"
      } >> "$GITHUB_OUTPUT"
      exit 0
    fi
    work=$(mktemp -d "$RUNNER_TEMP/texlive-installer.XXXXXX")
    installer= repository= year=
    for base in "${release_repositories[@]}"; do
      echo "Trying TeX Live installer: $base" >&2
      if ! archive_url=$(curl --fail --location --show-error --silent --retry 3 \
        --proto '=https' --proto-redir '=https' \
        --output "$work/installer.tar.gz" --write-out '%{url_effective}' \
        "$base/install-tl-unx.tar.gz"); then
        continue
      fi
      case "$archive_url" in
        https://*/install-tl-unx.tar.gz) candidate_repo=${archive_url%/install-tl-unx.tar.gz} ;;
        *) echo "Unexpected installer URL: $archive_url" >&2; continue ;;
      esac
      rm -rf -- "$work/installer"
      mkdir -p "$work/installer"
      if ! tar -xzf "$work/installer.tar.gz" -C "$work/installer" --strip-components=1; then
        echo "Cannot unpack installer from $base" >&2
        continue
      fi
      candidate_installer="$work/installer/install-tl"
      if [[ ! -f "$candidate_installer" ]]; then
        echo "Missing installer from $base" >&2
        continue
      fi
      version=$(perl "$candidate_installer" --version) || continue
      candidate_year=$(printf '%s\n' "$version" |
        sed -nE 's/^TeX Live .*version ([0-9]{4}).*/\1/p')
      if [[ "$candidate_year" == "$NT_TEXLIVE_YEAR" ]]; then
        installer=$candidate_installer
        repository=$candidate_repo
        year=$candidate_year
        break
      fi
      echo "Installer release $candidate_year differs from configured TeX Live $NT_TEXLIVE_YEAR; upgrade local and CI TeX Live together." >&2
    done
    if [[ -z "$installer" ]]; then
      echo "No installer for TeX Live $NT_TEXLIVE_YEAR could be downloaded; cannot build with current released packages." >&2
      exit 1
    fi
    {
      printf 'installer=%s\n' "$installer"
      printf 'repository=%s\n' "$repository"
      printf 'year=%s\n' "$year"
      printf 'day=%s\n' "$(date -u +%F)"
    } >> "$GITHUB_OUTPUT"
    ;;
  install)
    : "${RUNNER_TEMP:?}" "${NT_TEXLIVE_ROOT:?}" "${NT_TEXLIVE_YEAR:?}"
    : "${GITHUB_PATH:?}" "${GITHUB_OUTPUT:?}"
    mkdir -p diagnostics
    texbin="$NT_TEXLIVE_ROOT/bin/x86_64-linux"
    if installed_year=$(cached_year) && [[ "$installed_year" =~ ^[0-9]{4}$ ]]; then
      [[ "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
        echo "::error::Cached TeX Live $installed_year does not match configured release $NT_TEXLIVE_YEAR." >&2
        exit 1
      }
    else
      : "${NT_TEXLIVE_INSTALLER:?}" "${NT_TEXLIVE_REPOSITORY:?}"
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
      if ! perl "$NT_TEXLIVE_INSTALLER" --profile "$profile" \
        --repository "$NT_TEXLIVE_REPOSITORY" 2>&1 | tee diagnostics/texlive-install.log; then
        rm -f "$profile"
        echo "::error::TeX Live installation failed." >&2
        exit 1
      fi
      rm -f "$profile"
    fi

    export PATH="$texbin:$PATH"
    installed_year=$(cached_year) || installed_year=
    [[ "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
      echo "Unexpected TeX Live release: $installed_year" >&2; exit 1;
    }

    : "${NT_TEXLIVE_REPOSITORY:?}"
    tlmgr option autobackup 0
    preferred_repository=${NT_TEXLIVE_REPOSITORY%/}
    case "$preferred_repository" in
      https://mirror.ctan.org/*|https://mirrors.ctan.org/*)
        preferred_repository=${release_repositories[0]} ;;
    esac
    updated=false
    attempt=0
    declare -A tried_repositories=()
    : > diagnostics/texlive-update.log
    for repository in "$preferred_repository" "${release_repositories[@]}"; do
      [[ -z "${tried_repositories[$repository]:-}" ]] || continue
      tried_repositories[$repository]=true
      attempt=$((attempt + 1))
      attempt_log="diagnostics/texlive-update-attempt-$attempt.log"
      printf 'Update attempt %s: %s\n' "$attempt" "$repository" |
        tee -a diagnostics/texlive-update.log
      if ! tlmgr option repository "$repository" 2>&1 |
        tee "$attempt_log"; then
        cat "$attempt_log" >> diagnostics/texlive-update.log
        echo "::warning::Cannot select $repository; trying another mirror." >&2
        continue
      fi
      if tlmgr update --self --all --reinstall-forcibly-removed 2>&1 |
        tee -a "$attempt_log"; then
        cat "$attempt_log" >> diagnostics/texlive-update.log
        NT_TEXLIVE_REPOSITORY=$repository
        updated=true
        break
      fi
      cat "$attempt_log" >> diagnostics/texlive-update.log
      echo "::warning::TeX Live update failed at $repository; trying another mirror if available." >&2
    done
    if [[ "$updated" != true ]]; then
      echo "::error::TeX Live update failed on every candidate mirror; refusing to compile or reuse PDFs with unverified package freshness." >&2
      exit 1
    fi

    fmtutil-sys --byfmt lualatex 2>&1 | tee diagnostics/texlive-format.log
    luaotfload-tool --update 2>&1 | tee diagnostics/texlive-fonts.log
    printf '%s\n' "$texbin" >> "$GITHUB_PATH"
    {
      printf 'Repository: %s\n' "${NT_TEXLIVE_REPOSITORY}"
      date -u
      tlmgr --version
      lualatex --version
      latexmk --version
      biber --version
    } > diagnostics/toolchain.txt
    tlmgr info --only-installed > diagnostics/texlive-packages.txt
    printf '%s\n' '\documentclass{article}' \
      '\begin{document}\typeout{CI-LATEX-FORMAT: \fmtversion}CI format check.\end{document}' \
      > diagnostics/format-check.tex
    lualatex -interaction=nonstopmode -halt-on-error \
      -output-directory=diagnostics diagnostics/format-check.tex
    printf 'cacheable=true\n' >> "$GITHUB_OUTPUT"
    ;;
  *) echo "Usage: bash scripts/texlive-ci.sh inspect-cache|prepare|install" >&2; exit 2 ;;
esac
