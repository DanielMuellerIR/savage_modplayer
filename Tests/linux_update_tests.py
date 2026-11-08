"""Authentische Signaturen, unsichere Archive und fehlgeschlagene Versionswechsel."""
import base64
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'linux'))
import update
import install as installer


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='savage-update-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.prefix = self.root / 'prefix'
        self.bundle = self.prefix / 'lib/savage-mod-player/1.0.0-fixture'
        self.bundle.mkdir(parents=True)
        self.current = self.bundle.parent / 'current'
        self.current.symlink_to(self.bundle.name)
        (self.bundle / 'VERSION').write_text('1.0.0\n')
        self.private = self.root / 'fixture.pem'
        subprocess.run(['openssl','genpkey','-algorithm','ED25519','-out',str(self.private)],check=True,capture_output=True)
        der = subprocess.check_output(['openssl','pkey','-in',str(self.private),'-pubout','-outform','DER'])
        self.public = base64.b64encode(der[-32:]) + b'\n'
        (self.bundle / 'update-public-key.txt').write_bytes(self.public)
        self.updater = update.Updater(self.bundle)
        self.patch = patch.object(update.platform, 'machine', return_value='x86_64')
        self.patch.start(); self.addCleanup(self.patch.stop)
        self.data = dict(schema=1,product='savage-mod-player',arch='x86_64',version='1.0.1',size=100,
            sha256='0'*64,notes='Synthetic release',
            url=f'https://github.com/{update.REPOSITORY}/releases/download/v1.0.1/savage-mod-player-1.0.1-linux-x86_64.tar.gz')

    def signed(self, value):
        raw = json.dumps(value).encode()
        (self.root / 'manifest').write_bytes(raw)
        signature = subprocess.check_output(['openssl','pkeyutl','-sign','-inkey',str(self.private),'-rawin','-in',str(self.root / 'manifest')])
        return raw, base64.b64encode(signature)

    def test_signature_tampering_wrong_product_and_invalid_metadata(self):
        raw, sig = self.signed(self.data)
        self.assertEqual(self.updater.verify_manifest(raw,sig),self.data)
        for message,signature in [(raw+b' ',sig),(raw,b'invalid'),(raw,base64.b64encode(bytes(64)))]:
            with self.assertRaises(update.UpdateError): self.updater.verify_manifest(message,signature)
        for key,value in [('product','other'),('arch','aarch64'),('url','http://example.com'),('size',True),
                          ('size',2**40),('sha256','bad'),('version','1.2.3-rc'),('notes',[]),('schema',True)]:
            with self.subTest(key=key),self.assertRaises(update.UpdateError):
                self.updater.verify_manifest(*self.signed(dict(self.data,**{key:value})))
        with patch.object(self.updater,'fetch_manifest',return_value=self.data):
            self.assertEqual(self.updater.check(),self.data)
            (self.bundle/'VERSION').write_text('1.0.1\n')
            self.assertIsNone(self.updater.check())
            (self.bundle/'VERSION').write_text('2.0.0\n')
            self.assertIsNone(self.updater.check())

    def archive(self, entries):
        file=self.root/'fixture.tar.gz'
        with tarfile.open(file,'w:gz') as tar:
            for name,data,kind in entries:
                member=tarfile.TarInfo(name);member.type=kind;member.size=len(data);member.mode=0o755;member.linkname='/outside'
                tar.addfile(member,io.BytesIO(data))
        return file

    def test_paths_links_devices_duplicates_and_sources_are_rejected(self):
        for name,kind in [('../outside',tarfile.REGTYPE),('/absolute',tarfile.REGTYPE),
                          ('savage-mod-player-linux/../../outside',tarfile.REGTYPE),
                          ('savage-mod-player-linux/link',tarfile.SYMTYPE),('savage-mod-player-linux/hard',tarfile.LNKTYPE),
                          ('savage-mod-player-linux/fifo',tarfile.FIFOTYPE),('savage-mod-player-linux/device',tarfile.CHRTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as target, self.assertRaises(update.UpdateError):
                self.updater.extract(self.archive([(name,b'',kind)]),Path(target))
        with tempfile.TemporaryDirectory() as target,self.assertRaises(update.UpdateError):
            self.updater.extract(self.archive([('savage-mod-player-linux/a',b'x',tarfile.REGTYPE)]*2),Path(target))
        for url in ['http://github.com/file','https://example.com/file','https://user:password@github.com/file',
                    'https://github.com:444/file','file:///tmp/file']:
            with self.subTest(url=url),self.assertRaises(update.UpdateError): update.require_https(url)

    def test_inactive_installation_lock_cancellation_and_changed_offer(self):
        with patch.object(self.updater,'check',return_value=dict(self.data,sha256='1'*64)),self.assertRaises(update.UpdateError):
            self.updater.install(self.data)
        self.current.unlink()
        with self.assertRaises(update.UpdateError): self.updater.install(self.data)
        self.current.symlink_to(self.bundle.name)
        with installer.installation_lock(self.bundle.parent),self.assertRaises(update.UpdateError):
            self.updater.install(self.data)
        with patch.object(self.updater,'check',return_value=self.data),patch.object(self.updater,'download',side_effect=OSError('fixture')):
            with self.assertRaises(OSError): self.updater.install(self.data)
        with self.assertRaises(update.UpdateError): update.Updater(self.bundle,cancel=lambda:True).check_cancelled()
        self.assertEqual(self.current.resolve(),self.bundle)

    def package(self):
        source=self.root/'source';source.mkdir(exist_ok=True)
        for name in installer.FILES:
            (source/name).write_bytes(b'fixture')
        elf=b'\x7fELF\x02\x01'+bytes(12)+b'\x3e\x00'
        for name in ['savage-mod-player','savage-desktop-engine']: (source/name).write_bytes(elf)
        (source/'VERSION').write_text('1.0.1\n')
        (source/'update-public-key.txt').write_bytes(self.public)
        (source/'savage-mod-player.desktop').write_bytes((ROOT/'linux/savage-mod-player.desktop').read_bytes())
        (source/'install.py').write_bytes((ROOT/'linux/install.py').read_bytes())
        return source

    def test_authenticated_install_keeps_previous_and_rejects_changed_digest(self):
        source=self.package()
        (self.bundle/'install.py').write_bytes((ROOT/'linux/install.py').read_bytes())
        # Der neue Installer darf nicht aufgerufen werden: Die installierte
        # Version prüft und aktiviert das Paket.
        (source/'install.py').write_text('raise RuntimeError("new installer must not run")')
        (source/'future').mkdir()
        (source/'future/resource.txt').write_text('signed future resource')
        archive=self.root/'package.tar.gz'
        with tarfile.open(archive,'w:gz') as tar: tar.add(source,arcname='savage-mod-player-linux')
        data=dict(self.data,size=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest())
        def download(url,destination,limit):
            shutil.copyfile(archive,destination);return archive.stat().st_size
        with patch.object(self.updater,'check',return_value=data),patch.object(self.updater,'download',side_effect=download):
            with patch.dict(data,sha256='0'*64),self.assertRaises(update.UpdateError): self.updater.install(data)
            self.assertEqual(self.current.resolve(),self.bundle)
            original=importlib.util.module_from_spec
            def module(spec):
                result=original(spec)
                execute=spec.loader.exec_module
                def load(value):
                    execute(value);value.smoke=lambda source,cancelled:cancelled()
                spec.loader.exec_module=load
                return result
            with patch.object(update.importlib.util,'module_from_spec',side_effect=module):
                self.assertEqual(self.updater.install(data),'1.0.1')
        self.assertEqual((self.current/'VERSION').read_text(),'1.0.1\n')
        self.assertTrue(self.bundle.is_dir())
        self.assertEqual((self.current/'future/resource.txt').read_text(),'signed future resource')
        self.assertTrue((self.prefix/'bin/savage-mod-player').stat().st_mode & 0o111)

    def test_first_install_and_upgrade_failures_restore_files_and_modes(self):
        source=self.package()
        def fail(command,**values): raise subprocess.CalledProcessError(1,command)
        self.current.unlink()
        with patch.object(installer,'smoke'),patch.object(installer.shutil,'which',return_value='/fixture/tool'):
            with patch.object(installer.subprocess,'run',side_effect=fail),self.assertRaises(subprocess.CalledProcessError):
                installer.install(source,self.prefix)
            self.assertFalse((self.prefix/'bin/savage-mod-player').exists())
            self.assertFalse(self.current.is_symlink())
            with patch.object(installer.subprocess,'run',return_value=subprocess.CompletedProcess([],0)):
                installer.install(source,self.prefix)
            previous=self.current.resolve()
            launcher=self.prefix/'bin/savage-mod-player';before=launcher.read_bytes();mode=launcher.stat().st_mode
            desktop=self.prefix/'share/applications/savage-mod-player.desktop';desktop.write_text('custom entry')
            (source/'VERSION').write_text('1.0.2\n')
            with patch.object(installer.subprocess,'run',side_effect=fail),self.assertRaises(subprocess.CalledProcessError):
                installer.install(source,self.prefix)
            self.assertEqual(self.current.resolve(),previous)
            self.assertEqual(launcher.read_bytes(),before);self.assertEqual(launcher.stat().st_mode,mode)
            self.assertEqual(desktop.read_text(),'custom entry')

    def test_failure_after_pointer_swap_restores_previous_or_absent_installation(self):
        source=self.package()
        original=installer.os.replace
        launcher=self.prefix/'bin/savage-mod-player'
        def fail_launcher(source,destination):
            if Path(destination)==launcher: raise OSError('fixture after current switch')
            return original(source,destination)
        for previous in [self.bundle,None]:
            if self.current.is_symlink(): self.current.unlink()
            if previous: self.current.symlink_to(previous.name)
            with patch.object(installer,'smoke'),patch.object(installer.shutil,'which',return_value=None),patch.object(installer.os,'replace',side_effect=fail_launcher):
                with self.assertRaises(OSError): installer.install(source,self.prefix)
            self.assertFalse(launcher.exists())
            if previous: self.assertEqual(self.current.resolve(),previous)
            else: self.assertFalse(self.current.is_symlink())


if __name__=='__main__': unittest.main(verbosity=2)
