#!/usr/bin/env bash
# Rolling full TeX Live for GitHub-hosted Ubuntu x86_64 runners.
set -euo pipefail

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
    : "${RUNNER_TEMP:?}" "${GITHUB_OUTPUT:?}" "${NT_TEXLIVE_ROOT:?}"
    if installed_year=$(cached_year) && [[ "$installed_year" =~ ^[0-9]{4}$ ]]; then
      echo "::notice::Reusing cached TeX Live $installed_year; skipping installer download."
      {
        printf 'installer=\n'
        printf 'repository=%s\n' 'https://ctan.math.illinois.edu/systems/texlive/tlnet'
        printf 'year=%s\n' "$installed_year"
        printf 'day=%s\n' "$(date -u +%F)"
        printf 'offline=false\n'
      } >> "$GITHUB_OUTPUT"
      exit 0
    fi
    work=$(mktemp -d "$RUNNER_TEMP/texlive-installer.XXXXXX")
    installer= repository= year= offline=true
    for base in \
      https://mirrors.ctan.org/systems/texlive/tlnet \
      https://ctan.math.illinois.edu/systems/texlive/tlnet \
      https://mirror.math.princeton.edu/pub/CTAN/systems/texlive/tlnet; do
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
      if [[ "$candidate_year" =~ ^[0-9]{4}$ ]]; then
        installer=$candidate_installer
        repository=$candidate_repo
        year=$candidate_year
        offline=false
        break
      fi
    done
    if [[ "$offline" == true ]]; then
      year=$(cached_year) || year=
      [[ "$year" =~ ^[0-9]{4}$ ]] || {
        echo "No installer could be downloaded, and no usable cached TeX Live was found." >&2
        exit 1
      }
      echo "::warning::TeX Live discovery failed; reusing cached release $year without an update."
    fi
    {
      printf 'installer=%s\n' "$installer"
      printf 'repository=%s\n' "$repository"
      printf 'year=%s\n' "$year"
      printf 'day=%s\n' "$(date -u +%F)"
      printf 'offline=%s\n' "$offline"
    } >> "$GITHUB_OUTPUT"
    ;;
  install)
    : "${RUNNER_TEMP:?}" "${NT_TEXLIVE_ROOT:?}" "${NT_TEXLIVE_YEAR:?}"
    : "${GITHUB_PATH:?}" "${GITHUB_OUTPUT:?}"
    mkdir -p diagnostics
    texbin="$NT_TEXLIVE_ROOT/bin/x86_64-linux"
    cacheable=false
    from_cache=false
    prior_cache=
    if installed_year=$(cached_year) && [[ "$installed_year" =~ ^[0-9]{4}$ ]]; then
      from_cache=true
    fi

    if [[ "${NT_TEXLIVE_OFFLINE:-false}" == true ]]; then
      [[ "$from_cache" == true && "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
        echo "Offline TeX Live requested, but the cached release cannot be used." >&2
        exit 1
      }
    else
      : "${NT_TEXLIVE_INSTALLER:?}" "${NT_TEXLIVE_REPOSITORY:?}"
      if [[ "$from_cache" == true && "$installed_year" != "$NT_TEXLIVE_YEAR" ]]; then
        echo "::warning::Cached TeX Live $installed_year differs from mirror release $NT_TEXLIVE_YEAR; keeping the cached release."
        NT_TEXLIVE_YEAR=$installed_year
        NT_TEXLIVE_OFFLINE=true
      fi
      if [[ "$from_cache" == false ]]; then
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
        if perl "$NT_TEXLIVE_INSTALLER" --profile "$profile" \
          --repository "$NT_TEXLIVE_REPOSITORY" 2>&1 | tee diagnostics/texlive-install.log &&
          [[ "$(cached_year)" == "$NT_TEXLIVE_YEAR" ]]; then
          :
        elif [[ -n "$prior_cache" ]]; then
          echo "::warning::New TeX Live installation failed; restoring the older cached release."
          rm -rf -- "$NT_TEXLIVE_ROOT"
          mv -- "$prior_cache/texlive" "$NT_TEXLIVE_ROOT"
          rm -rf -- "$prior_cache"
          NT_TEXLIVE_YEAR=$installed_year
          NT_TEXLIVE_OFFLINE=true
          from_cache=true
        else
          echo "TeX Live installation failed and no cached release is available." >&2
          exit 1
        fi
        rm -f "$profile"
      fi
    fi

    export PATH="$texbin:$PATH"
    installed_year=$(cached_year) || installed_year=
    [[ "$installed_year" == "$NT_TEXLIVE_YEAR" ]] || {
      echo "Unexpected TeX Live release: $installed_year" >&2; exit 1;
    }

    if [[ "${NT_TEXLIVE_OFFLINE:-false}" == true || "${NT_TEXLIVE_EXACT_CACHE_HIT:-false}" == true ]]; then
      echo "::notice::Using cached TeX Live $installed_year; updates skipped (offline or exact daily cache hit)."
    else
      snapshot=
      can_update=true
      if [[ "$from_cache" == true ]]; then
        size_kb=$(du -sk "$NT_TEXLIVE_ROOT" | cut -f1)
        free_kb=$(df -Pk "$RUNNER_TEMP" | awk 'END {print $4}')
        if (( free_kb < size_kb + 1048576 )); then
          echo "::warning::Not enough disk space to safeguard the TeX Live cache; skipping update."
          can_update=false
        else
          snapshot=$(mktemp -d "$RUNNER_TEMP/texlive-backup.XXXXXX")
          if ! cp -a --reflink=auto "$NT_TEXLIVE_ROOT" "$snapshot/texlive"; then
            echo "::warning::Could not safeguard the TeX Live cache; skipping update."
            rm -rf -- "$snapshot"
            snapshot=
            can_update=false
          fi
        fi
      fi
      if [[ "$can_update" == true ]]; then
        if tlmgr option repository "$NT_TEXLIVE_REPOSITORY" &&
           tlmgr option autobackup 0 &&
           { tlmgr update --self 2>&1 | tee diagnostics/texlive-update-self.log; } &&
           { tlmgr update --all 2>&1 | tee diagnostics/texlive-update-all.log; }; then
          cacheable=true
        elif [[ "$from_cache" == true && -n "$snapshot" ]]; then
          echo "::warning::TeX Live update failed; restoring the unchanged cached installation."
          rm -rf -- "$NT_TEXLIVE_ROOT"
          mv -- "$snapshot/texlive" "$NT_TEXLIVE_ROOT"
          cacheable=false
        elif [[ -n "$prior_cache" ]]; then
          echo "::warning::TeX Live update failed; restoring the previous cached release."
          rm -rf -- "$NT_TEXLIVE_ROOT"
          mv -- "$prior_cache/texlive" "$NT_TEXLIVE_ROOT"
          NT_TEXLIVE_YEAR=$(cached_year)
          NT_TEXLIVE_OFFLINE=true
          cacheable=false
        else
          echo "TeX Live update failed, and no cached installation is available." >&2
          exit 1
        fi
      fi
      if [[ -n "$snapshot" ]]; then
        rm -rf -- "$snapshot"
      fi
    fi

    if [[ -n "$prior_cache" ]]; then
      rm -rf -- "$prior_cache"
    fi
    fmtutil-sys --byfmt lualatex-dev 2>&1 | tee diagnostics/texlive-format.log
    luaotfload-tool --update 2>&1 | tee diagnostics/texlive-fonts.log
    printf '%s\n' "$texbin" >> "$GITHUB_PATH"
    {
      printf 'Repository: %s\n' "${NT_TEXLIVE_REPOSITORY:-cached (offline)}"
      date -u
      tlmgr --version
      lualatex-dev --version
      latexmk --version
      biber --version
    } > diagnostics/toolchain.txt
    tlmgr info --only-installed > diagnostics/texlive-packages.txt
    printf '%s\n' '\documentclass{article}' \
      '\begin{document}\typeout{CI-LATEX-FORMAT: \fmtversion}CI format check.\end{document}' \
      > diagnostics/format-check.tex
    lualatex-dev -interaction=nonstopmode -halt-on-error \
      -output-directory=diagnostics diagnostics/format-check.tex
    printf 'cacheable=%s\n' "$cacheable" >> "$GITHUB_OUTPUT"
    ;;
  *) echo "Usage: bash scripts/texlive-ci.sh inspect-cache|prepare|install" >&2; exit 2 ;;
esac
