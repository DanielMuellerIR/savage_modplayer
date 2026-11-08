#!/usr/bin/env python3
"""Benutzerinstallation mit unveränderlichen Versionen und atomarem Versionswechsel."""
import argparse
import base64
import contextlib
import fcntl
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import tempfile

FILES = ("savage-mod-player", "savage-desktop-engine", "VERSION", "update-public-key.txt",
         "update.py", "install.py", "AppIcon.png", "savage-mod-player.desktop", "savage-collection.xml", "LICENSE", "Swift-LICENSE.txt")


def package_files(source):
    files, size = [], 0
    for count, file in enumerate(source.rglob('*'), 1):
        if count > 20000 or file.is_symlink() or not (file.is_file() or file.is_dir()):
            raise ValueError("Unsicherer oder zu großer Paketinhalt.")
        if '__pycache__' in file.parts or file.suffix == '.pyc':
            continue
        if file.is_file():
            size += file.stat().st_size
            if size > 1024 ** 3 or file.stat().st_size > 512 * 1024 * 1024:
                raise ValueError("Das entpackte Paket ist zu groß.")
            files.append(file.relative_to(source))
    for name in FILES:
        if Path(name) not in files:
            raise ValueError(f"Unvollständiges Paket: {name}")
    return sorted(files)


def digest(source):
    value = hashlib.sha256()
    for name in package_files(source):
        file = source / name
        value.update(str(name).encode() + b'\0' + str(file.stat().st_size).encode() + b'\0'
                     + (b'x' if file.stat().st_mode & 0o111 else b'-'))
        with file.open("rb") as stream:
            for block in iter(lambda: stream.read(1048576), b""):
                value.update(block)
    return value.hexdigest()


@contextlib.contextmanager
def installation_lock(root):
    descriptor = os.open(root / ".update-lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Eine andere Installation oder Aktualisierung läuft bereits.") from error
        yield
    finally:
        os.close(descriptor)


def smoke(source, cancelled):
    cancelled()
    crypto = subprocess.run(["openssl", "version"], capture_output=True, timeout=5, check=True).stdout
    if not re.match(rb"OpenSSL [3-9]\.", crypto):
        raise ValueError("OpenSSL 3 wird für Update-Signaturen benötigt.")
    with tempfile.TemporaryDirectory(prefix="savage-install-smoke-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, SAVAGE_DESKTOP_DATA=str(root / "data"), QT_QPA_PLATFORM="offscreen")
        actual = subprocess.run([str(source / "savage-mod-player"), "--version"],
                                capture_output=True, text=True, env=env, timeout=10, check=True).stdout.strip()
        if actual != "Savage Mod Player " + (source / "VERSION").read_text().strip():
            raise ValueError("Die Oberfläche meldet eine andere Paketversion.")
        result = subprocess.run([str(source / "savage-desktop-engine")], input='{"command":"quit"}\n',
                                text=True, capture_output=True, env=env, timeout=20, check=True)
        if not any('"event":"ready"' in line.replace(" ", "") for line in result.stdout.splitlines()):
            raise ValueError("Die neue Audio-Engine ist nicht startfähig.")
        cancelled()
        subprocess.run([str(source / "savage-mod-player"), "--engine", str(source / "savage-desktop-engine"),
                        "--screenshot", str(root / "smoke.png"), "--capture-delay", "300"],
                       capture_output=True, env=env, timeout=15, check=True)
        if not (root / "smoke.png").is_file():
            raise ValueError("Die neue Oberfläche ist nicht startfähig.")
    cancelled()


def desktop_exec(executable):
    def quote(value):
        if any(char in value for char in "\n\r\t"):
            raise ValueError("Zeilenumbrüche und Tabs sind im Installationspfad nicht zulässig.")
        for old, new in [("\\", "\\\\\\\\"), ('"', '\\\\"'), ("$", "\\\\$"), ("`", "\\\\`"), ("%", "%%")]:
            value = value.replace(old, new)
        return '"' + value + '"'
    return 'Exec=/bin/sh -c ' + quote('exec "$@"') + ' savage-mod-player ' + quote(str(executable)) + ' %F'


def install(source, prefix, *, lock_held=False, cancelled=lambda: None):
    source, prefix = Path(source).resolve(), Path(prefix).resolve()
    if prefix in (Path("/"), Path.home()):
        raise ValueError("Ein eigener Installationspräfix ist erforderlich.")
    package_digest = digest(source)
    version = (source / "VERSION").read_text().strip()
    if not re.fullmatch(r"[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}", version):
        raise ValueError("Ungültige Paketversion.")
    key = base64.b64decode((source / "update-public-key.txt").read_bytes().strip(), validate=True)
    if len(key) != 32:
        raise ValueError("Ungültiger Updateschlüssel.")
    for name in ("savage-mod-player", "savage-desktop-engine"):
        with (source / name).open("rb") as file:
            header = file.read(20)
        if header[:6] != b"\x7fELF\x02\x01" or header[18:20] != b"\x3e\x00":
            raise ValueError("Das Paket benötigt Linux x86_64.")
    root = prefix / "lib/savage-mod-player"
    if root == source or source in root.parents:
        raise ValueError("Das Installationsziel darf nicht im Paket liegen.")
    if root.is_symlink():
        raise ValueError("Das Installationsverzeichnis darf kein Symlink sein.")
    root.mkdir(parents=True, exist_ok=True)
    with (contextlib.nullcontext() if lock_held else installation_lock(root)):
        smoke(source, cancelled)
        target = root / f"{version}-{package_digest[:16]}"
        if target.exists():
            if target.is_symlink() or digest(target) != package_digest:
                raise ValueError("Ein bestehendes Versionsverzeichnis wurde verändert.")
        else:
            stage = Path(tempfile.mkdtemp(prefix=".install-", dir=root))
            try:
                for name in package_files(source):
                    (stage / name).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source / name, stage / name)
                    (stage / name).chmod(0o755 if (source / name).stat().st_mode & 0o111 else 0o644)
                if digest(stage) != package_digest:
                    raise ValueError("Das Paket wurde während der Installation verändert.")
                stage.rename(target)
            finally:
                if stage.exists():
                    shutil.rmtree(stage)
        current = root / "current"
        if current.exists() and not current.is_symlink():
            raise ValueError("Der aktuelle Installationspfad ist kein Versionszeiger.")
        snapshots = []

        def remember(destination, allow_link=False):
            if destination.is_symlink():
                if not allow_link:
                    raise ValueError(f"Ziel ist keine reguläre Datei: {destination.name}")
                snapshots.append((destination, "link", os.readlink(destination), None))
            elif destination.is_file():
                snapshots.append((destination, "file", destination.read_bytes(), stat.S_IMODE(destination.stat().st_mode)))
            elif destination.exists():
                raise ValueError(f"Kein ersetzbarer App-Pfad: {destination.name}")
            else:
                snapshots.append((destination, "absent", None, None))

        def put_file(destination, data, mode=0o644):
            remember(destination)
            descriptor, pending = tempfile.mkstemp(prefix=".savage-install-", dir=destination.parent)
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(data)
                os.chmod(pending, mode)
                os.replace(pending, destination)
            finally:
                if os.path.exists(pending):
                    os.unlink(pending)

        try:
            binary = prefix / "bin"
            applications = prefix / "share/applications"
            icons = prefix / "share/icons/hicolor/256x256/apps"
            mime = prefix / "share/mime/packages"
            for folder in (binary, applications, icons, mime):
                folder.mkdir(parents=True, exist_ok=True)
            launcher = binary / "savage-mod-player"
            desktop = '\n'.join(desktop_exec(launcher) if line.startswith('Exec=') else line
                                for line in (target / "savage-mod-player.desktop").read_text().splitlines()) + '\n'
            put_file(applications / "savage-mod-player.desktop", desktop.encode())
            old_cli = applications / "savage-cli.desktop"
            backup = applications / "savage-cli.desktop.before-gui"
            if backup.is_symlink():
                raise ValueError("Die Sicherung des CLI-Starteintrags ist keine reguläre Datei.")
            if old_cli.exists() and not backup.exists():
                if old_cli.is_symlink():
                    raise ValueError("Der alte CLI-Starteintrag ist keine reguläre Datei.")
                put_file(backup, old_cli.read_bytes())
            if backup.exists():
                put_file(old_cli, (desktop + '\nNoDisplay=true\n').encode())
            put_file(icons / "savage-mod-player.png", (target / "AppIcon.png").read_bytes())
            put_file(mime / "savage-collection.xml", (target / "savage-collection.xml").read_bytes())
            for command, folder in (("update-desktop-database", applications), ("update-mime-database", mime.parent)):
                if shutil.which(command):
                    subprocess.run([command, str(folder)], check=True, capture_output=True, timeout=15)
            cancelled()
            remember(current, allow_link=True)
            descriptor, pending = tempfile.mkstemp(prefix=".current-", dir=root)
            os.close(descriptor)
            os.unlink(pending)
            try:
                os.symlink(target.name, pending)
                os.replace(pending, current)
            finally:
                if os.path.lexists(pending):
                    os.unlink(pending)
            put_file(launcher, ('#!/bin/sh\nexec ' + shlex.quote(str(current / 'savage-mod-player')) + ' "$@"\n').encode(), 0o755)
        except BaseException:
            for destination, kind, value, mode in reversed(snapshots):
                if destination.is_symlink() or destination.is_file():
                    destination.unlink()
                if kind == "link":
                    destination.symlink_to(value)
                elif kind == "file":
                    destination.write_bytes(value)
                    destination.chmod(mode)
            raise
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--prefix", type=Path, default=Path.home() / ".local")
    args = parser.parse_args()
    def interrupted(number, frame):
        raise SystemExit(128 + number)
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, interrupted)
    try:
        version = install(args.source, args.prefix)
    except Exception as error:
        import sys
        print(f"Installation fehlgeschlagen: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"INSTALL OK: {args.prefix / 'bin/savage-mod-player'} ({version})")
