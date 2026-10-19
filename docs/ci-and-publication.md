# CI and PDF publication

## Architecture

The **book repository**, `EgbertRijke/number-theory`
(`git@github.com:EgbertRijke/number-theory.git`), compiles and hosts its PDFs through its own GitHub
Pages project site. The **egbertrijke.github.io repository** only links to
those files. No cross-repository token, personal access token, generated-PDF
commits, release updates, or second deployment workflow is needed.

The existing website at `/notes/number-theory/` can keep its introduction and
other content. Add the download links there once publication succeeds.
Use this workflow in the book repository, not in `egbertrijke.github.io`:
a Pages deployment replaces that repository's entire Pages site.

## What builds

`.github/workflows/book.yml` runs on branch pushes and manual dispatches.
It uses the existing Makefile without changing the typography or TeX sources:

| Profile | Local command | Output with the current three volume drivers |
| --- | --- | --- |
| Canonical | `make all` | Omnibus and volumes 1, 2, 3 |
| Canvas / Ally | `make ally all` | Omnibus and volumes 1, 2, 3, with `-ally` filenames |

Both use `DEFAULT_FONT` from the Makefile (currently Libertinus), plus the
supporting font choices already declared in the preamble. Do not pass
`FONT=libertinus`: an explicit font selection changes the output filenames.
`make fonts` is intentionally not used. Classroom materials are not book
editions and are not included.

Both profiles build sequentially on one runner, using exactly the same updated
installation. The volumes are built together using the existing auxiliary-file
convergence logic; they must not be split into independent jobs. CI selects
`lualatex-dev` for both the bootstrap passes and every latexmk pass through
`ENGINE=lualatex-dev` and `LATEXMK='latexmk -r scripts/latexmk-ci.rc'`.
The ordinary local Makefile defaults remain unchanged. New consecutive `volume-N.tex` drivers are discovered
automatically by both Make and the publication script.

Build artifacts contain the PDFs. Diagnostic artifacts contain TeX/Biber logs
and the engine/package versions, including on build failure. These artifacts
expire after 14 days; the published Pages PDFs do not inherit that expiry.
Do not use Actions artifact URLs as public download links: they require login
and expire.

## One-time activation

The repository is currently private. Start with compilation only: leave
`PUBLISH_PDFS` unset. The generated PDFs will be available as Actions artifacts
to authorized repository users. No Pages setup is needed for this stage.
Private-repository Actions usage is subject to your plan's included usage and
billing settings. Repository visibility does not need to change to run CI.

Enable the publication steps below only when you want the PDFs publicly
available. Hosting a public Pages site does not require making the source
public when your GitHub plan supports Pages from private repositories.


1. Copy these files into the book repository, commit, and push:
   - `.github/workflows/book.yml`
   - `scripts/book-publication.py`
   - `scripts/texlive-ci.sh`
   - `scripts/latexmk-ci.rc`
   - `docs/ci-and-publication.md`
   - `README.md`
   - `.gitignore`
2. In **Actions**, open **Build and publish book**. Verify that the build job completes both PDF profiles
   successfully. With no publication variable set, the workflow only builds; the
   package and deploy jobs are skipped. Download the PDF artifacts and inspect
   the results before enabling publication.
3. In the **book repository**, select **Settings → Pages → Build and deployment
   → Source → GitHub Actions**. If Pages is unavailable, check the repository's
   visibility and your plan. GitHub Free supports Pages from public repositories;
   Pages from private repositories requires an eligible paid plan. A Pages site
   can be public even when its source repository is private.
4. In **Settings → Secrets and variables → Actions → Variables**, create the
   repository variable `PUBLISH_PDFS` with the exact value `true`.
5. In **Actions → Build and publish book → Run workflow**, select the default
   branch. Subsequent pushes to that branch publish automatically. The workflow
   discovers the default branch; it does not assume `main` or `master`.
6. Follow the URL in the **github-pages** deployment environment. Check the
   landing page and all eight PDF downloads, then add the links below to your
   existing website. Keep the `github-pages` environment restricted to the
   default branch if you configure deployment branch restrictions.

No secret is required. The automatic `GITHUB_TOKEN` has read access during
compilation; only the deployment job receives Pages and OIDC write permissions.
`PUBLISH_PDFS` is a variable, not a secret. If repository or organization policies
restrict Actions, permit the official `actions/*` actions used in the workflow.

To pause future publication, delete `PUBLISH_PDFS` or set it to `false`.
This does not remove already-published PDFs. To remove the site, use Pages
settings. Other branches build but never publish. Pull request events are not
needed; pushes to your own branches run CI even without using pull requests.
If you later want fork PR checks, add `pull_request:` alongside `push:`; keep
the default-branch publication condition and do not use `pull_request_target`.

## Stable links from egbertrijke.github.io

For `EgbertRijke/number-theory`, the default project site is:

```text
https://egbertrijke.github.io/number-theory/
```

These URLs become available only after the first successful Pages deployment.
Use the deployed base URL shown in the environment if a custom domain changes it.

Paste this HTML into the existing book page (HTML also works in Jekyll Markdown):

```html
<h2>Download The Great Story of Numbers</h2>
<p>Current working drafts, updated after successful builds.</p>
<ul>
  <li><a href="https://egbertrijke.github.io/number-theory/number-theory.pdf">Complete book (PDF)</a></li>
  <li><a href="https://egbertrijke.github.io/number-theory/number-theory-volume-1.pdf">Volume 1 (PDF)</a></li>
  <li><a href="https://egbertrijke.github.io/number-theory/number-theory-volume-2.pdf">Volume 2 (PDF)</a></li>
  <li><a href="https://egbertrijke.github.io/number-theory/number-theory-volume-3.pdf">Volume 3 (PDF)</a></li>
</ul>
<p><a href="https://egbertrijke.github.io/number-theory/">All downloads, including Canvas / Ally editions</a></p>
```

The Ally filenames are `number-theory-ally.pdf` and
`number-theory-volume-1-ally.pdf` through `number-theory-volume-3-ally.pdf`.
The generated landing page links to every edition and displays the build time,
source commit, sizes, and a JSON checksum manifest. The links stay unchanged
across updates.

All PDFs are published in the same directory, preserving the relative
filenames used by `setup/save-state.tex`. Cross-PDF navigation depends on the
reader; browser PDF viewers may not support those links. For offline use,
download all three volumes of the same profile into one folder.

Your existing page currently includes a manually written update date and page
count. Remove or update those claims when changing its download links; the new
landing page supplies build metadata automatically. Existing links to PDFs
stored at older paths will continue to point to those older files until you
change them; this setup does not redirect them automatically.

## Rolling TeX Live and LaTeX development

Every workflow run downloads the current upstream TeX Live installer and
identifies its release year. The workflow restores a cached full installation
for that year, or installs `scheme-full` when no cache exists. Documentation
and package source files are omitted to reduce download and cache size; runtime
packages and fonts are included. The bundled cuneiform font is unchanged.

**Every run, including exact cache hits**, executes:

```sh
tlmgr update --self
tlmgr update --all
fmtutil-sys --byfmt lualatex-dev
luaotfload-tool --update
```

The installer and updates use the same resolved HTTPS CTAN mirror for a run.
An unsuccessful download or update stops the workflow; it does not silently
compile with the old cached installation. “Up to date” means the newest
packages available from that mirror at update time; CTAN and TeX Live packaging
and mirror synchronization introduce some delay after an upstream commit.

CI uses **`lualatex-dev`**, LaTeX's published development/pre-release format.
This follows the latest pre-release shipped through TeX Live, alongside current
`latex-lab`, tagging packages, fonts, and Biber. It does not build arbitrary
unreleased Git commits of LaTeX or LuaTeX. The format is regenerated after
updates, and a small compilation records the actual kernel version in
`diagnostics/format-check.log`. `--version` alone only identifies the engine.

Both canonical and Ally PDFs build with this same installation. The saved
package inventory and logs record what was actually used. There is deliberately
no image digest or package-version pin. The old `TEXLIVE_IMAGE` variable is no
longer read and can be deleted if it was configured.

### Cache lifetime

This is a persistent GitHub Actions **disk cache**, not RAM retained between
runners. The cache holds the installation, generated formats, and initial font
database. Its key includes the runner platform, TeX Live release year, setup
script hash, and UTC date. The most recent compatible older cache can seed the
next run. GitHub caches are immutable, so the first successful setup of a UTC
day saves that day's snapshot; later runs still fetch any subsequent updates.

The refreshed cache is saved immediately after successful setup. A later
compilation error therefore does not waste the installation work. A new annual
TeX Live release gets a separate cache and a fresh install automatically;
`tlmgr` is not asked to perform an unsupported cross-year update.

GitHub controls cache retention and eviction. Unused caches are normally
removed after seven days, and storage limits can evict them earlier. Full
TeX Live snapshots are large, so only a few daily snapshots may fit. Cache
eviction changes startup time, not the package-freshness policy. No cleanup
job or extra token is needed for correctness.

There is no scheduled trigger: updates happen on each existing push or manual
workflow run. No periodic rebuild is needed to make a new run fresh.

## Failure behavior and local checks

Publication depends on both profiles compiling successfully and the full PDF set passing
packaging checks. Failure before deployment leaves the previous site in place.
Generated `dist/`, `_site/`, and `diagnostics/` directories are ignored by Git.
Only selected PDFs, the download page, and its metadata are published; the
source archive and diagnostic logs are not part of the Pages site.

To exercise packaging locally after compiling:

```sh
make all
python3 scripts/book-publication.py collect --profile canonical
mkdir -p _site
cp dist/*.pdf _site/
make ally all
python3 scripts/book-publication.py collect --profile ally
cp dist/*.pdf _site/
python3 scripts/book-publication.py site
```

Remove stale PDFs from `_site/` first if the volume set changed. `collect`
replaces PDFs in generated `dist/`; it never changes the root build outputs.
A full CI run always starts with fresh generated directories.

The initial publication setup was checked for YAML structure, Makefile command
routing, complete packaging, and rejection of incomplete PDF sets. The rolling
installer and development-format selection have additionally been checked with
mock tools; a live upstream installation has not been run here. Full TeX compilation and a
live Pages deployment have not been verified here: the preparation environment
has TeX Live 2023, and GitHub account access was not connected.

## Upstream documentation

- [GitHub Pages custom workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [GitHub Pages overview](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
- [Actions artifact behavior](https://github.com/actions/upload-artifact)
- [TeX Live installer](https://tug.org/texlive/doc/install-tl.html)
- [TeX Live package manager](https://tug.org/texlive/doc/tlmgr.html)
- [LaTeX development format](https://ctan.org/pkg/latex-base-dev)
- [GitHub cache behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
