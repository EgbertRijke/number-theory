#!/usr/bin/env python3
"""Prepare an isolated Jekyll build using the current personal website theme.

No source pages from the website are copied. Only the generated book subtree
will be deployed; shared root assets remain owned by the website workflow.
"""
import argparse
from pathlib import Path
import shutil


def prepare(website, publication, output):
    if output.exists():
        raise ValueError(f'Output already exists: {output}')
    if not (website / '_config.yml').is_file():
        raise ValueError('Website source must contain _config.yml.')
    if not (publication / 'notes/number-theory/index.md').is_file():
        raise ValueError('Generated book index.md is missing.')
    output.mkdir(parents=True)
    for name in ('_config.yml', '_layouts', '_includes', '_sass', '_data', 'assets'):
        source = website / name
        if source.is_symlink():
            raise ValueError(f'Refusing a theme symlink: {source}')
        if source.is_dir():
            shutil.copytree(source, output / name)
        elif source.is_file():
            shutil.copy2(source, output / name)
    shutil.copytree(publication / 'notes', output / 'notes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--website', type=Path, required=True)
    parser.add_argument('--publication', type=Path, default=Path('_publication'))
    parser.add_argument('--output', type=Path, default=Path('_book-source'))
    args = parser.parse_args()
    prepare(args.website, args.publication, args.output)
