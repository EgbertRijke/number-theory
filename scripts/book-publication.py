#!/usr/bin/env python3
"""Collect PDFs and generate the Jekyll page owned by the book repository.

Run from the repository root. `site` requires PyMuPDF and pdftoppm (Poppler).
Output is the book page source tree, rendered with the website theme before deployment.
"""
import argparse
from datetime import datetime, timezone
import hashlib
from html import escape
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

BASE = '/notes/number-theory/'
PAGE = 'notes/number-theory/index.md'
ASSETS = Path('notes/number-theory')


def editions():
    numbers = sorted(int(m.group(1)) for p in Path('.').glob('volume-*.tex')
                     if (m := re.fullmatch(r'volume-([1-9][0-9]*)\.tex', p.name)))
    if not numbers or numbers != list(range(1, max(numbers) + 1)):
        raise SystemExit('Expected consecutive volume-N.tex drivers starting at 1.')
    return [('number-theory', 'Complete book')] + [
        (f'number-theory-volume-{n}', f'Volume {n}') for n in numbers]


def filename(stem, profile):
    return stem + ('-ally' if profile == 'ally' else '') + '.pdf'


def check_pdf(path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f'Missing regular PDF: {path}')
    with path.open('rb') as stream:
        if stream.read(5) != b'%PDF-':
            raise SystemExit(f'Invalid PDF header: {path}')
    if path.stat().st_size >= 100 * 1024 * 1024:
        raise SystemExit(f'{path} exceeds GitHub’s individual Git file size limit.')


def collect(profile):
    paths = [Path(filename(stem, profile)) for stem, _ in editions()]
    for path in paths:
        check_pdf(path)
    destination = Path('dist')
    destination.mkdir(exist_ok=True)
    for path in destination.glob('*.pdf'):
        path.unlink()
    for path in paths:
        shutil.copy2(path, destination / path.name)
    print(f'Collected {len(paths)} {profile} PDFs in {destination}/')


def markdown_text(text):
    # PDF bookmarks have already resolved TeX accents, macros and PDF strings.
    text = escape(' '.join(text.split()), quote=False)
    return re.sub(r'([\\`*_\[\]])', r'\\\1', text)


def contents_markdown(outline):
    """Use hyperref destination types, not nesting guesses (front/back matter)."""
    lines = []
    counts = {'part': 0, 'chapter': 0}
    for level, title, page, target in outline:
        dest = target.get('nameddest', '')
        kind = re.split(r'[.*]', dest, maxsplit=1)[0]
        if kind == 'appendix':
            kind = 'chapter'
        if kind not in ('part', 'chapter', 'section', 'subsection'):
            raise ValueError(f'Unrecognized bookmark destination {dest!r}: {title!r}. '
                             'Check the PDF outline before publishing.')
        if page < 1:
            raise ValueError(f'Bookmark without a local page: {title!r}')
        title = markdown_text(title)
        if kind == 'part':
            counts['part'] += 1
            lines.extend(['', f'### {title}', ''])
        else:
            counts['chapter'] += kind == 'chapter'
            indent = {'chapter': '', 'section': '  ', 'subsection': '    '}[kind]
            lines.append(f'{indent}- {title}')
    if not counts['part'] or not counts['chapter']:
        raise ValueError('Expected parts and chapters in the complete-book PDF outline.')
    return '\n'.join(lines).strip() + '\n'


def site(pdf_dir, destination):
    import pymupdf

    expected = [filename(stem, profile) for stem, _ in editions()
                for profile in ('canonical', 'ally')]
    actual = {p.name for p in pdf_dir.glob('*.pdf')}
    if actual != set(expected):
        raise ValueError(f'Incomplete PDF set; missing={set(expected) - actual}, '
                         f'unexpected={actual - set(expected)}')
    for name in expected:
        check_pdf(pdf_dir / name)
    if destination.exists():
        raise ValueError(f'{destination} already exists; choose a fresh output directory.')
    if not shutil.which('pdftoppm'):
        raise ValueError('Install Poppler (pdftoppm) to generate cover PNGs.')
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    commit = os.environ.get('GITHUB_SHA', 'local build')
    manifest = {'commit': commit, 'built_at': stamp, 'files': {}}
    # Build in a temporary directory: incomplete results cannot be published.
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        root = Path(temporary)
        assets = root / ASSETS
        assets.mkdir(parents=True)
        for name in expected:
            path = pdf_dir / name
            with pymupdf.open(path) as pdf:
                if pdf.needs_pass or pdf.page_count < 1:
                    raise ValueError(f'Unreadable or empty PDF: {name}')
                pages = pdf.page_count
                if name == 'number-theory.pdf':
                    contents = contents_markdown(pdf.get_toc(simple=False))
            shutil.copy2(path, assets / name)
            manifest['files'][name] = {
                'bytes': path.stat().st_size, 'pages': pages,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        cards, rows = [], []
        for stem, label in editions():
            subprocess.run(['pdftoppm', '-f', '1', '-l', '1', '-singlefile',
                            '-scale-to', '1000', '-png', str(pdf_dir / (stem + '.pdf')),
                            str(assets / stem)], check=True)
            png = assets / (stem + '.png')
            if not png.is_file() or png.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError(f'Cover generation failed: {png}')
            cards.append(f'''<div class="book-edition">
<a class="book-cover" href="{BASE}{stem}.pdf">
<img src="{BASE}{stem}.png" alt="Download {escape(label)} — The Great Story of Numbers (PDF)" width="773" height="1000">
<span>{escape(label)}</span></a>
<a class="book-canvas" href="{BASE}{stem}-ally.pdf">Canvas version</a>
</div>''')
            cells = []
            for profile in ('canonical', 'ally'):
                name = filename(stem, profile)
                info = manifest['files'][name]
                cells.append(f'<td><a href="{BASE}{name}">PDF</a> '
                             f'<small>({info["pages"]} pages; '
                             f'{info["bytes"] / 1024**2:.1f} MiB)</small></td>')
            rows.append(f'<tr><th scope="row">{escape(label)}</th>{"".join(cells)}</tr>')
        downloads = '''<link rel="stylesheet" href="/notes/number-theory/book.css">

<div class="book-editions" aria-label="Download an edition">
''' + '\n'.join(cards) + '''
</div>

<div class="book-downloads">
<table>
<caption>Download the complete book or an individual volume</caption>
<thead><tr><th scope="col">Edition</th><th scope="col">Main version</th>
<th scope="col">Canvas / Ally</th></tr></thead>
<tbody>
''' + '\n'.join(rows) + '''
</tbody></table>
</div>

The main versions use the book’s PDF 2.0 and MathML configuration.
The Canvas / Ally versions use its PDF 1.7 compatibility configuration.
For links between volumes when reading offline, download all three volumes
of the same version into one folder and keep their filenames unchanged.
Support for links between PDF files varies between viewers.
'''
        info = (f'Current working drafts. Last built: **{stamp}**.\n\n'
                f'[Build details and PDF checksums]({BASE}build.json).')
        template = Path('site/landing.md').read_text(encoding='utf-8')
        for token, value in [('DOWNLOADS', downloads), ('BUILD_INFO', info),
                             ('CONTENTS', contents)]:
            marker = f'@@{token}@@'
            if template.count(marker) != 1:
                raise ValueError(f'Expected exactly one {marker} in site/landing.md')
            template = template.replace(marker, value)
        # Prevent a title containing Liquid syntax from executing as a template.
        template = template.replace('{%', '&#123;%').replace('{{', '&#123;{')
        (root / PAGE).write_text(template, encoding='utf-8')
        (assets / 'contents.md').write_text('# Table of contents\n\n' + contents, encoding='utf-8')
        (assets / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        shutil.copy2('site/book.css', assets / 'book.css')
        shutil.copytree(root, destination)
    print(f'Prepared {len(expected)} PDFs, covers, contents and Jekyll page in {destination}/')


def legacy(pdf_dir, destination):
    """Keep old direct PDF URLs working; redirect only the former landing page."""
    if destination.exists():
        raise ValueError(f'{destination} already exists; choose a fresh output directory.')
    destination.mkdir(parents=True)
    for stem, _ in editions():
        for profile in ('canonical', 'ally'):
            source = pdf_dir / filename(stem, profile)
            check_pdf(source)
            shutil.copy2(source, destination / source.name)
    url = 'https://egbertrijke.github.io' + BASE
    (destination / 'index.html').write_text(f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The Great Story of Numbers</title><link rel="canonical" href="{url}">
<meta http-equiv="refresh" content="0; url={url}"></head>
<body><p><a href="{url}">The Great Story of Numbers has moved here.</a></p></body></html>
''', encoding='utf-8')
    (destination / '.nojekyll').touch()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    cp = commands.add_parser('collect')
    cp.add_argument('--profile', choices=('canonical', 'ally'), required=True)
    for name in ('site', 'legacy'):
        sp = commands.add_parser(name)
        sp.add_argument('--pdf-dir', type=Path, default=Path('_pdfs'))
        sp.add_argument('--output', type=Path, default=Path('_publication' if name == 'site' else '_site'))
    args = parser.parse_args()
    if args.command == 'collect':
        collect(args.profile)
    else:
        try:
            (site if args.command == 'site' else legacy)(args.pdf_dir, args.output)
        except (ValueError, subprocess.CalledProcessError) as exc:
            parser.exit(1, f'Publication failed: {exc}\n')


if __name__ == '__main__':
    main()
