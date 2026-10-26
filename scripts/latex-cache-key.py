#!/usr/bin/env python3

import hashlib
from pathlib import Path
import subprocess


WEBSITE_ONLY_FILES = {
    'README.md',
    'LATEX-CACHE.md',
    'scripts/book-publication.py',
    'scripts/publication-requirements.txt',
    'scripts/prepare-book-site.py',
    'scripts/publish-site.py',
}
WEBSITE_ONLY_DIRECTORIES = {'site', '.github'}


def fingerprint():
    tracked = subprocess.check_output(['git', 'ls-files', '-z']).split(b'\0')
    digest = hashlib.sha256()
    count = 0
    for name in sorted(set(tracked) - {b''}):
        path = Path(name.decode('utf-8'))
        if (path.as_posix() in WEBSITE_ONLY_FILES
                or path.parts[0] in WEBSITE_ONLY_DIRECTORIES):
            continue
        digest.update(len(name).to_bytes(8, 'big'))
        digest.update(name)
        digest.update(hashlib.sha256(path.read_bytes()).digest())
        count += 1
    if not count:
        raise SystemExit('No tracked book inputs found; refusing an empty cache key.')
    return digest.hexdigest()


if __name__ == '__main__':
    print(fingerprint())
