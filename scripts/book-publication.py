#!/usr/bin/env python3
"""Collect PDFs and generate the Jekyll page owned by the book repository.

Run from the repository root. `site` requires PyMuPDF and pdftoppm (Poppler).
Output is the book page source tree, rendered with the website theme before deployment.
"""
import argparse
from datetime import datetime, timezone
from html import escape
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

    roman = {1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V', 6: 'VI', 7: 'VII'}

    return [('number-theory', 'Single-Volume Edition')] + [
        (f'number-theory-volume-{n}', f'Book {roman[n]}') for n in numbers]

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


def render_placeholders(template, values):
    """Substitute generated fields, leaving no unresolved template markers."""
    for key, value in values.items():
        template = template.replace(f'@@{key}@@', str(value))
    return template


def expand_repeated_block(template, name, replacements):
    """Repeat a block defined in landing.md for each edition."""
    begin = f'<!-- BEGIN {name} -->'
    end = f'<!-- END {name} -->'
    if template.count(begin) != 1 or template.count(end) != 1:
        raise ValueError(f'Expected exactly one {begin} and {end} in site/landing.md')
    before, rest = template.split(begin, 1)
    fragment, after = rest.split(end, 1)
    expanded = '\n'.join(render_placeholders(fragment.strip('\n'), values)
                         for values in replacements)
    return before + expanded + after


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
    today = datetime.now(timezone.utc)
    stamp = f'{today:%B} {today.day}, {today.year}'
    manifest = {'files': {}}
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
                'bytes': path.stat().st_size,
                'pages': pages}
        edition_fields = []
        for stem, label in editions():
            subprocess.run(['pdftoppm', '-f', '1', '-l', '1', '-singlefile',
                            '-scale-to', '1000', '-png', str(pdf_dir / (stem + '.pdf')),
                            str(assets / stem)], check=True)
            png = assets / (stem + '.png')
            if not png.is_file() or png.read_bytes()[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError(f'Cover generation failed: {png}')
            main = filename(stem, 'canonical')
            ally = filename(stem, 'ally')
            main_info = manifest['files'][main]
            ally_info = manifest['files'][ally]
            edition_fields.append({
                'EDITION_LABEL': escape(label),
                'MAIN_PDF_URL': BASE + main,
                'ALLY_PDF_URL': BASE + ally,
                'COVER_PNG_URL': BASE + stem + '.png',
                'MAIN_PAGES': main_info['pages'],
                'ALLY_PAGES': ally_info['pages'],
                'MAIN_MIB': f"{main_info['bytes'] / 1024**2:.1f}",
                'ALLY_MIB': f"{ally_info['bytes'] / 1024**2:.1f}",
            })
        template = Path('site/landing.md').read_text(encoding='utf-8')
        template = expand_repeated_block(template, 'EDITION_CARDS', edition_fields)
        for name in ('BUILT_AT', 'CONTENTS'):
            marker = f'@@{name}@@'
            if template.count(marker) != 1:
                raise ValueError(f'Expected exactly one {marker} in site/landing.md')
        template = render_placeholders(template, {'BUILT_AT': stamp, 'CONTENTS': contents})
        leftover = re.findall(r'@@[A-Z][A-Z0-9_]*@@', template)
        if leftover:
            raise ValueError(f'Unresolved landing page placeholders: {leftover}')
        # Prevent a title containing Liquid syntax from executing as a template.
        template = template.replace('{%', '&#123;%').replace('{{', '&#123;{')
        (root / PAGE).write_text(template, encoding='utf-8')
        (assets / 'contents.md').write_text('# Table of contents\n\n' + contents, encoding='utf-8')
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
