#!/usr/bin/env python3
"""Collect only expected PDFs and prepare a complete GitHub Pages publication.

Uses the standard library. Run from the repository root after `make all` or
`make ally all`. Does not compile TeX or certify PDF accessibility.
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


def editions():
    numbers = sorted(
        int(match.group(1))
        for path in Path('.').glob('volume-*.tex')
        if (match := re.fullmatch(r'volume-([1-9][0-9]*)\.tex', path.name))
    )
    if not numbers or numbers != list(range(1, max(numbers) + 1)):
        raise SystemExit('Expected consecutive volume-N.tex drivers starting at 1.')
    return [('number-theory', 'Complete book')] + [
        (f'number-theory-volume-{n}', f'Volume {n}') for n in numbers
    ]


def filename(stem, profile):
    return stem + ('-ally' if profile == 'ally' else '') + '.pdf'


def check_pdf(path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f'Missing regular PDF: {path}')
    with path.open('rb') as stream:
        if stream.read(5) != b'%PDF-':
            raise SystemExit(f'Invalid PDF header: {path}')


def collect(profile):
    paths = [Path(filename(stem, profile)) for stem, _ in editions()]
    for path in paths:
        check_pdf(path)
    destination = Path('dist')
    destination.mkdir(exist_ok=True)
    # This directory is generated; remove stale PDFs from a previous local run.
    for path in destination.glob('*.pdf'):
        path.unlink()
    for path in paths:
        shutil.copy2(path, destination / path.name)
    print(f'Collected {len(paths)} {profile} PDFs in {destination}/')


def site():
    destination = Path('_site')
    expected = [filename(stem, profile) for stem, _ in editions()
                for profile in ('canonical', 'ally')]
    actual = {path.name for path in destination.glob('*.pdf')}
    if actual != set(expected):
        raise SystemExit(f'Incomplete PDF set; missing={set(expected) - actual}, '
                         f'unexpected={actual - set(expected)}')
    for name in expected:
        check_pdf(destination / name)
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    # This is the checked-out commit, also for a manually selected branch.
    commit = os.environ.get('GITHUB_SHA', 'local build')
    manifest = {
        'commit': commit,
        'built_at': stamp,
        'files': {
            name: {'bytes': (destination / name).stat().st_size,
                   'sha256': hashlib.sha256((destination / name).read_bytes()).hexdigest()}
            for name in expected
        },
    }
    (destination / 'build.json').write_text(
        json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    rows = []
    for stem, label in editions():
        cells = []
        for profile in ('canonical', 'ally'):
            name = filename(stem, profile)
            size = (destination / name).stat().st_size / (1024 * 1024)
            cells.append(f'<td><a href="{escape(name)}">PDF '
                         f'<span class="size">({size:.1f} MiB)</span></a></td>')
        rows.append(f'<tr><th scope="row">{escape(label)}</th>{"".join(cells)}</tr>')
    (destination / 'index.html').write_text('''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The Great Story of Numbers — PDFs</title>
<style>
body {max-width: 52rem; margin: 3rem auto; padding: 0 1rem;
      font: 1.1rem/1.6 Georgia, serif; color: #222; background: #faf9f6;}
a {color: #15558d;} h1 {line-height: 1.2;}
table {border-collapse: collapse; width: 100%; margin: 2rem 0;}
th, td {text-align: left; padding: .65rem .4rem; border-bottom: 1px solid #bbb;}
.size, footer {font-size: .9rem;} code {overflow-wrap: anywhere;}
</style></head><body><main>
<h1>The Great Story of Numbers</h1><p>Egbert Rijke</p>
<p>Current working drafts, compiled with the book’s default fonts.</p>
<table><caption>Download the complete book or individual volumes</caption>
<thead><tr><th scope="col">Edition</th><th scope="col">Canonical</th>
<th scope="col">Canvas / Ally</th></tr></thead><tbody>
''' + '\n'.join(rows) + f'''
</tbody></table>
<p>The canonical edition uses the book’s PDF 2.0 and MathML configuration.
The Canvas / Ally edition uses its PDF 1.7 compatibility configuration.</p>
<p>For links between volumes when reading offline, download all three volumes
of the same edition into one folder and keep their filenames unchanged.
Support for links to other PDF files varies between PDF viewers.</p>
<p><a href="https://egbertrijke.github.io/notes/number-theory/">About the book</a>
 · <a href="https://egbertrijke.github.io/">Author’s website</a></p>
</main><footer>Built {escape(stamp)} · Commit <code>{escape(commit)}</code>
 · <a href="build.json">Build details and checksums</a></footer></body></html>
''', encoding='utf-8')
    (destination / '.nojekyll').touch()
    print(f'Prepared {len(expected)} PDFs and index.html in {destination}/')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    collect_parser = commands.add_parser('collect')
    collect_parser.add_argument('--profile', choices=('canonical', 'ally'), required=True)
    commands.add_parser('site')
    args = parser.parse_args()
    if args.command == 'collect':
        collect(args.profile)
    else:
        site()


if __name__ == '__main__':
    main()
