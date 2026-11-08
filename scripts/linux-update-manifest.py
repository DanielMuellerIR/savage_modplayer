#!/usr/bin/env python3
"""Erstellt und prüft das signierte Linux-Release-Manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'linux'))
from update import verify_signature, MAX_PACKAGE
from install import FILES


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text().strip()
    if args.archive.name != f'savage-mod-player-{version}-linux-x86_64.tar.gz' or not 0 < args.archive.stat().st_size <= MAX_PACKAGE:
        raise ValueError('Falscher Paketname oder unzulässige Paketgröße.')
    key = (ROOT / 'config/sparkle-public-key.txt').read_bytes()
    with tarfile.open(args.archive, 'r:gz') as archive:
        members = {}
        size = 0
        for count, member in enumerate(archive, 1):
            size += member.size
            if count > 20000 or member.size < 0 or member.size > MAX_PACKAGE or size > 1024 ** 3:
                raise ValueError('Entpacktes Paket ist zu groß.')
            parts = Path(member.name).parts
            if (not parts or parts[0] != 'savage-mod-player-linux' or '..' in parts
                    or Path(member.name).is_absolute() or member.name in members
                    or not (member.isfile() or member.isdir())):
                raise ValueError('Unsicherer Archivinhalt.')
            members[member.name] = member
        for name in FILES:
            if not members['savage-mod-player-linux/' + name].isfile():
                raise ValueError('Unvollständiges Paket.')
        def read(name, limit=1024):
            return archive.extractfile('savage-mod-player-linux/' + name).read(limit)
        if read('VERSION').decode().strip() != version or read('update-public-key.txt') != key:
            raise ValueError('Paketversion oder Updateschlüssel stimmen nicht.')
        for name in ['savage-mod-player', 'savage-desktop-engine']:
            data = read(name, 20)
            if data[:6] != b'\x7fELF\x02\x01' or data[18:20] != b'\x3e\x00':
                raise ValueError('Linux-x86_64-Programme erwartet.')
    digest = hashlib.sha256()
    with args.archive.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''): digest.update(block)
    document = dict(schema=1,product='savage-mod-player',arch='x86_64',version=version,
        url=f'https://github.com/DanielMuellerIR/savage_modplayer/releases/download/v{version}/{args.archive.name}',
        size=args.archive.stat().st_size,sha256=digest.hexdigest(),
        notes=args.notes.read_text()[:12000] if args.notes else '')
    if args.verify:
        raw = args.output.read_bytes()
        verify_signature(raw,args.output.with_suffix('.json.sig').read_bytes(),ROOT / 'config/sparkle-public-key.txt')
        if json.loads(raw) != document: raise ValueError('Signiertes Manifest passt nicht zum Release-Paket.')
    else:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(document,ensure_ascii=False,sort_keys=True)+'\n')


if __name__ == '__main__': main()
