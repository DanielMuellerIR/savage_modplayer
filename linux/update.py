"""Signierte GitHub-Vollupdates für die bestehende Benutzerinstallation."""

import base64
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request

REPOSITORY = "DanielMuellerIR/savage_modplayer"
FEED = "https://danielmuellerir.github.io/savage_modplayer/linux/stable.json"
MAX_PACKAGE = 512 * 1024 * 1024


class UpdateError(Exception):
    pass


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}", value):
        raise UpdateError("Ungültige Update-Version.")
    return tuple(map(int, value.split(".")))


def require_https(url):
    parts = urllib.parse.urlsplit(url)
    if (parts.scheme != "https" or parts.username or parts.password
            or parts.port not in (None, 443) or parts.fragment
            or parts.hostname not in {"github.com", "release-assets.githubusercontent.com",
                                      "objects.githubusercontent.com", "danielmuellerir.github.io"}):
        raise UpdateError("Unzulässige Updatequelle.")


class Redirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        require_https(url)
        return super().redirect_request(request, fp, code, message, headers, url)


def verify_signature(raw, signature, public_key):
    if len(raw) > 65536 or len(signature) > 256:
        raise UpdateError("Updatebeschreibung ist zu groß.")
    try:
        key = base64.b64decode(Path(public_key).read_bytes().strip(), validate=True)
        sig = base64.b64decode(signature.strip(), validate=True)
        if len(key) != 32 or len(sig) != 64:
            raise ValueError()
    except ValueError as error:
        raise UpdateError("Die Update-Signatur ist ungültig.") from error
    with tempfile.TemporaryDirectory(prefix="savage-update-signature-") as temporary:
        folder = Path(temporary)
        # RFC 8410 SubjectPublicKeyInfo für den fest eingebetteten Ed25519-Schlüssel.
        (folder / "key.der").write_bytes(bytes.fromhex("302a300506032b6570032100") + key)
        (folder / "manifest").write_bytes(raw)
        (folder / "signature").write_bytes(sig)
        try:
            result = subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER",
                "-inkey", str(folder / "key.der"), "-rawin", "-in", str(folder / "manifest"),
                "-sigfile", str(folder / "signature")], capture_output=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise UpdateError("Zur Signaturprüfung wird OpenSSL 3 benötigt.") from error
        if result.returncode != 0:
            raise UpdateError("Die Update-Signatur ist ungültig.")


class Updater:
    def __init__(self, bundle, cancel=None, progress=None):
        self.bundle = Path(bundle).resolve()
        self.cancel = cancel or (lambda: False)
        self.progress = progress or (lambda current, total: None)
        self.opener = urllib.request.build_opener(Redirects())

    def check_cancelled(self):
        if self.cancel():
            raise UpdateError("Aktualisierung abgebrochen.")

    def download(self, url, destination, limit):
        require_https(url)
        request = urllib.request.Request(url, headers={"User-Agent": "SavageModPlayer-Updater/1"})
        size = 0
        deadline = time.monotonic() + 600
        with self.opener.open(request, timeout=20) as response, Path(destination).open("xb") as output:
            length = response.headers.get("Content-Length")
            if length and int(length) > limit:
                raise UpdateError("Update-Download ist zu groß.")
            while True:
                self.check_cancelled()
                if time.monotonic() > deadline:
                    raise UpdateError("Zeitlimit beim Update-Download überschritten.")
                block = response.read(65536)
                if not block:
                    break
                size += len(block)
                if size > limit:
                    raise UpdateError("Update-Download ist zu groß.")
                output.write(block)
                self.progress(size, int(length) if length else limit)
        return size

    def verify_manifest(self, raw, signature):
        verify_signature(raw, signature, self.bundle / "update-public-key.txt")
        try:
            data = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise UpdateError("Updatebeschreibung ist unlesbar.") from error
        if (not isinstance(data, dict) or data.get("product") != "savage-mod-player"
                or type(data.get("schema")) is not int or data.get("schema") != 1 or data.get("arch") != "x86_64"
                or platform.machine() != "x86_64"):
            raise UpdateError("Das Update gehört nicht zu dieser Anwendung oder Plattform.")
        candidate = data.get("version")
        version(candidate)
        expected = f"https://github.com/{REPOSITORY}/releases/download/v{candidate}/savage-mod-player-{candidate}-linux-x86_64.tar.gz"
        if (data.get("url") != expected or type(data.get("size")) is not int
                or not 0 < data["size"] <= MAX_PACKAGE
                or not isinstance(data.get("sha256"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", data["sha256"])
                or not isinstance(data.get("notes", ""), str)
                or len(data.get("notes", "")) > 12000):
            raise UpdateError("Ungültige Paketangaben im Update.")
        return data

    def fetch_manifest(self):
        with tempfile.TemporaryDirectory(prefix="savage-update-check-") as temporary:
            raw, signature = Path(temporary) / "manifest", Path(temporary) / "signature"
            self.download(FEED, raw, 65536)
            self.download(FEED + ".sig", signature, 256)
            return self.verify_manifest(raw.read_bytes(), signature.read_bytes())

    def check(self):
        data = self.fetch_manifest()
        current = (self.bundle / "VERSION").read_text().strip()
        return data if version(data["version"]) > version(current) else None

    def installation(self):
        root = self.bundle.parent
        current = root / "current"
        if (root.name != "savage-mod-player" or root.parent.name != "lib"
                or not current.is_symlink() or current.resolve() != self.bundle
                or root.stat().st_uid != os.getuid()):
            raise UpdateError("Updates sind nur in der aktiven Benutzerinstallation möglich. Installiere diese Version zunächst mit install.sh oder starte den Player nach einem Update neu.")
        return root, root.parent.parent

    def install(self, expected):
        root, prefix = self.installation()
        descriptor = os.open(root / ".update-lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise UpdateError("Eine andere Aktualisierung läuft bereits.") from error
            self.installation()
            data = self.check()
            if data is None or any(data[key] != expected[key] for key in ("version", "sha256")):
                raise UpdateError("Das Updateangebot hat sich geändert. Bitte erneut prüfen.")
            with tempfile.TemporaryDirectory(prefix=".update-", dir=root) as temporary:
                work = Path(temporary)
                archive = work / "package.tar.gz"
                size = self.download(data["url"], archive, data["size"])
                digest = hashlib.sha256()
                with archive.open("rb") as source:
                    for block in iter(lambda: source.read(1048576), b""):
                        self.check_cancelled()
                        digest.update(block)
                if size != data["size"] or digest.hexdigest() != data["sha256"]:
                    raise UpdateError("Das Paket stimmt nicht mit der signierten Prüfsumme überein.")
                stage = work / "package"
                stage.mkdir()
                self.extract(archive, stage)
                package = stage / "savage-mod-player-linux"
                if ((package / "VERSION").read_text().strip() != data["version"]
                        or (package / "update-public-key.txt").read_bytes()
                        != (self.bundle / "update-public-key.txt").read_bytes()):
                    raise UpdateError("Paketversion oder Updateschlüssel stimmen nicht überein.")
                self.check_cancelled()
                self.installation()
                # Der bereits installierte Installer bleibt die Vertrauensbasis.
                spec = importlib.util.spec_from_file_location("savage_update_installer", self.bundle / "install.py")
                installer = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(installer)
                installer.install(package, prefix, lock_held=True, cancelled=self.check_cancelled)
                return data["version"]
        finally:
            os.close(descriptor)

    def extract(self, archive, destination):
        with tarfile.open(archive, "r:gz") as tar:
            seen, size = set(), 0
            for count, member in enumerate(tar, 1):
                self.check_cancelled()
                path = PurePosixPath(member.name)
                if (count > 20000 or path.is_absolute() or ".." in path.parts
                        or not path.parts or path.parts[0] != "savage-mod-player-linux"
                        or not (member.isfile() or member.isdir()) or path in seen):
                    raise UpdateError("Unsicherer Archivpfad oder Dateityp im Update.")
                seen.add(path)
                size += member.size
                if member.size < 0 or member.size > MAX_PACKAGE or size > 1024 ** 3:
                    raise UpdateError("Entpacktes Update ist zu groß.")
                target = destination.joinpath(*path.parts)
                if member.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as source, target.open("xb") as output:
                        shutil.copyfileobj(source, output, 1048576)
                    target.chmod(0o755 if member.mode & 0o111 else 0o644)


def main():
    import argparse
    import signal
    import sys
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--action", choices=["check", "install"], required=True)
    args = parser.parse_args()
    def interrupted(number, frame):
        raise UpdateError("Aktualisierung abgebrochen.")
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, interrupted)
    def emit(event, **values):
        print(json.dumps(dict(event=event, **values), ensure_ascii=False), flush=True)
    try:
        updater = Updater(args.bundle, progress=lambda current, total: emit("progress", value=current / max(1, total)))
        if args.action == "check":
            emit("offer", offer=updater.check())
        else:
            raw = sys.stdin.buffer.read(65537)
            if len(raw) > 65536:
                raise UpdateError("Updateangebot ist zu groß.")
            expected = json.loads(raw)
            if not isinstance(expected, dict):
                raise UpdateError("Ungültiges Updateangebot.")
            emit("installed", version=updater.install(expected))
    except Exception as error:
        emit("error", message=str(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
