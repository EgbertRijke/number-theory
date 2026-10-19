#!/usr/bin/env python3
"""Publish a scoped build into the website's deployment-only Git branch.

IMPORTANT: --checkout must be a DISPOSABLE clean CI checkout of the destination
repository. This command resets that checkout while retrying ordinary pushes.
No force-push is used. The book owns notes/number-theory; the website owns the
remaining deployment tree. Both workflows use this same helper.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

BOOK = Path('notes/number-theory')


def git(checkout, *args, check=True):
    return subprocess.run(['git', '-C', str(checkout), *args], check=check,
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def remove(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def overlay(build, checkout, scope):
    """Apply one publisher's files, preserving everything owned by the other."""
    if scope == 'book':
        source = build / BOOK
        if not (source / 'index.html').is_file():
            raise ValueError('Rendered book index.html is missing.')
        if not (checkout / 'index.html').is_file():
            raise ValueError('Publish the main website to the deployment branch first.')
        target = checkout / BOOK
        if (checkout / 'notes').is_symlink() or target.is_symlink():
            raise ValueError('Refusing a symlink in the book destination.')
        if target.exists():
            remove(target)
        target.parent.mkdir(exist_ok=True)
        shutil.copytree(source, target)
    else:
        if not (build / 'index.html').is_file():
            raise ValueError('Rendered website index.html is missing.')
        if (build / BOOK).exists():
            raise ValueError('Website build contains the reserved book path; remove the old book page.')
        # Remove stale website files but preserve the book subtree.
        for path in checkout.iterdir():
            if path.name == '.git':
                continue
            if path.name == 'notes' and path.is_dir() and not path.is_symlink():
                for child in path.iterdir():
                    if child.name != 'number-theory':
                        remove(child)
            else:
                remove(path)
        shutil.copytree(build, checkout, dirs_exist_ok=True)
    (checkout / '.nojekyll').touch()


def publish(build, checkout, branch, scope):
    build, checkout = build.resolve(), checkout.resolve()
    if not (checkout / '.git').exists():
        raise ValueError('Expected a disposable Git checkout.')
    if build == checkout or checkout in build.parents or build in checkout.parents:
        raise ValueError('Build and checkout must be separate directories.')
    git(checkout, 'check-ref-format', '--branch', branch)
    source_branch = git(checkout, 'symbolic-ref', '--short', 'HEAD', check=False).stdout.strip()
    if branch == source_branch:
        raise ValueError('Deployment branch must differ from the checked-out source branch.')
    if git(checkout, 'status', '--porcelain').stdout.strip():
        raise ValueError('Disposable checkout must start clean.')
    for path in build.rglob('*'):
        if path.is_symlink() or path.name == '.git':
            raise ValueError(f'Unsafe build entry: {path}')
    git(checkout, 'config', 'user.name', 'github-actions[bot]')
    git(checkout, 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
    for attempt in range(3):
        remote = git(checkout, 'ls-remote', '--exit-code', '--heads', 'origin',
                     'refs/heads/' + branch, check=False)
        if remote.returncode == 0:
            git(checkout, 'fetch', 'origin', 'refs/heads/' + branch)
            git(checkout, 'checkout', '-B', 'publication-work', 'FETCH_HEAD')
            git(checkout, 'reset', '--hard', 'FETCH_HEAD')
            git(checkout, 'clean', '-fdx')
        elif remote.returncode == 2:
            if scope != 'website':
                raise ValueError('Deployment branch is missing. Run the website workflow first.')
            git(checkout, 'checkout', '--orphan', f'publication-initial-{attempt}')
            git(checkout, 'rm', '-rf', '--ignore-unmatch', '.')
            git(checkout, 'clean', '-fdx')
        else:
            raise ValueError('Cannot inspect destination branch: ' + remote.stderr)
        overlay(build, checkout, scope)
        git(checkout, 'add', '-A')
        if git(checkout, 'diff', '--cached', '--quiet', check=False).returncode == 0:
            print('Deployment content is unchanged.')
            return
        commit = os.environ.get('GITHUB_SHA', 'local build')
        git(checkout, 'commit', '-m', f'Publish {scope} from {commit}')
        pushed = git(checkout, 'push', 'origin', 'HEAD:refs/heads/' + branch, check=False)
        if pushed.returncode == 0:
            print(f'Published {scope} to deployment branch {branch}.')
            return
        # Re-read the latest remote tree and reapply only our scope. This
        # preserves a concurrent publication by the other repository.
    raise ValueError('Push failed after three attempts: ' + pushed.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--scope', choices=('book', 'website'), required=True)
    args = parser.parse_args()
    try:
        publish(args.build, args.checkout, args.branch, args.scope)
    except (ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Publication failed: {exc}\n')
