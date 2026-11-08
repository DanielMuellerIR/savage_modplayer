"""Signiertes Folgepaket über den echten Qt-Koordinator installieren, während Audio weiterläuft."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'linux'))
import install as installer
from update import FEED,REPOSITORY
from mpris_contract_tests import silent_mod,PLAYER,PROPS,PATH


def main():
    if not sys.platform.startswith('linux') or not os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
        raise RuntimeError('Linux und ein isolierter Sitzungsbus sind erforderlich.')
    with tempfile.TemporaryDirectory(prefix='savage-update-integration-') as temporary:
        work=Path(temporary)
        build=ROOT/'.build/linux-gui'
        source=work/'source';source.mkdir()
        for name in installer.FILES:
            origin=build/name
            if name=='AppIcon.png': origin=ROOT/'src/AppIcon.png'
            elif name in ('savage-mod-player.desktop','savage-collection.xml'): origin=ROOT/'linux'/name
            elif name=='LICENSE': origin=ROOT/name
            elif name=='Swift-LICENSE.txt': origin=ROOT/'linux/licenses'/name
            shutil.copyfile(origin,source/name)
            if name in ('savage-mod-player','savage-desktop-engine'): (source/name).chmod(0o755)
        version=(source/'VERSION').read_text().strip()
        numbers=version.split('.');numbers[-1]=str(int(numbers[-1])+1);following='.'.join(numbers)
        fixture_source=work/'candidate-source'
        shutil.copytree(ROOT/'linux/gui',fixture_source/'linux/gui')
        for file in ('update.py','install.py'): shutil.copyfile(ROOT/'linux'/file,fixture_source/'linux'/file)
        (fixture_source/'config').mkdir();shutil.copyfile(ROOT/'config/sparkle-public-key.txt',fixture_source/'config/sparkle-public-key.txt')
        (fixture_source/'linux/licenses').mkdir();shutil.copyfile(ROOT/'linux/licenses/Swift-LICENSE.txt',fixture_source/'linux/licenses/Swift-LICENSE.txt')
        (fixture_source/'src').mkdir();shutil.copyfile(ROOT/'src/AppIcon.png',fixture_source/'src/AppIcon.png')
        (fixture_source/'VERSION').write_text(following+'\n')
        candidate_build=work/'candidate-build'
        subprocess.run(['cmake','-S',str(fixture_source/'linux/gui'),'-B',str(candidate_build),'-DCMAKE_BUILD_TYPE=Release','-DBUILD_TESTING=OFF'],check=True,stdout=subprocess.DEVNULL)
        subprocess.run(['cmake','--build',str(candidate_build),'--parallel','4'],check=True,stdout=subprocess.DEVNULL)
        key=work/'fixture.pem';subprocess.run(['openssl','genpkey','-algorithm','ED25519','-out',str(key)],check=True)
        public=base64.b64encode(subprocess.check_output(['openssl','pkey','-in',str(key),'-pubout','-outform','DER'])[-32:])+b'\n'
        (source/'update-public-key.txt').write_bytes(public)
        candidate=work/'candidate';shutil.copytree(source,candidate)
        shutil.copyfile(candidate_build/'savage-mod-player',candidate/'savage-mod-player');(candidate/'savage-mod-player').chmod(0o755)
        (candidate/'VERSION').write_text(following+'\n')
        archive=work/f'savage-mod-player-{following}-linux-x86_64.tar.gz'
        with tarfile.open(archive,'w:gz') as tar: tar.add(candidate,arcname='savage-mod-player-linux')
        url=f'https://github.com/{REPOSITORY}/releases/download/v{following}/{archive.name}'
        document=dict(schema=1,product='savage-mod-player',arch='x86_64',version=following,
            size=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),url=url,notes='<b>Signed fixture update</b>\nPlayback stays active.')
        manifest=work/'stable.json';manifest.write_text(json.dumps(document))
        signature=work/'stable.json.sig'
        signature.write_bytes(base64.b64encode(subprocess.check_output(['openssl','pkeyutl','-sign','-rawin','-inkey',str(key),'-in',str(manifest)])))
        mapping={FEED:str(manifest),FEED+'.sig':str(signature),url:str(archive)}
        # Nur der Transport ist eine eigene Fixture. Signaturprüfung, Entpacken,
        # Startprüfung, alter Installer und Qt-Prozesskanal laufen unverändert.
        wrapper='''
def fixture_download(self,url,destination,limit):
    source=Path(MAPPING[url])
    if source.stat().st_size > limit: raise UpdateError('fixture size')
    shutil.copyfile(source,destination)
    self.progress(source.stat().st_size,source.stat().st_size)
    return source.stat().st_size
Updater.download=fixture_download
'''.replace('MAPPING',repr(mapping))
        code=(source/'update.py').read_text();code=code.replace('if __name__ == "__main__":',wrapper+'\nif __name__ == "__main__":')
        (source/'update.py').write_text(code)
        prefix=work/'prefix';installer.install(source,prefix)
        current=prefix/'lib/savage-mod-player/current';previous=current.resolve()
        fixture=work/'playing.mod';fixture.write_bytes(silent_mod())
        config=work/'alsa.conf';config.write_text('pcm.!default { type null }\n')
        data=work/'data';data.mkdir();(data/'preferences.json').write_text(json.dumps(dict(loop='track')))
        preserved=data/'library-unrelated.bin';preserved.write_bytes(b'preserve user data')
        env=dict(os.environ,QT_QPA_PLATFORM='offscreen',ALSA_CONFIG_PATH=str(config),SAVAGE_DESKTOP_DATA=str(data))
        process=subprocess.Popen([str(current/'savage-mod-player'),str(fixture)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        def status():
            return subprocess.run(['gdbus','call','--session','--dest',f'org.mpris.MediaPlayer2.savage.desktop{process.pid}',
                '--object-path',PATH,'--method',PROPS+'.Get',PLAYER,'PlaybackStatus'],capture_output=True,text=True,timeout=3).stdout
        try:
            deadline=time.monotonic()+10
            while 'Playing' not in status() and time.monotonic()<deadline: time.sleep(.05)
            assert 'Playing' in status()
            capture=work/'offer.png'
            image_env=dict(env,SAVAGE_DESKTOP_DATA=str(work/'capture-data'))
            subprocess.run([str(current/'savage-mod-player'),'--review-view','updates','--capture-delay','1200','--screenshot',str(capture)],env=image_env,check=True,capture_output=True,timeout=10)
            destination=os.environ.get('SAVAGE_UPDATE_SCREENSHOT')
            if destination: shutil.copyfile(capture,destination)
            native_env=dict(env,SAVAGE_UPDATE_FIXTURE_BUNDLE=str(previous),SAVAGE_UPDATE_FIXTURE_VERSION=following)
            subprocess.run([str(build/'savage-update-tests'),'authenticatedPackageInstall'],env=native_env,check=True,timeout=75)
            assert current.resolve()!=previous and (current/'VERSION').read_text().strip()==following
            assert previous.is_dir() and 'Playing' in status() and process.poll() is None
            assert preserved.read_bytes()==b'preserve user data'
            print('Authenticated Qt update, new GUI/engine smoke, atomic activation, old version and live playback preserved: OK')
        finally:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill();process.wait(timeout=3)
        launched = subprocess.run([str(prefix/'bin/savage-mod-player'), '--version'],env=env,
                                 capture_output=True,text=True,check=True,timeout=10)
        assert launched.stdout.strip() == 'Savage Mod Player ' + following
        subprocess.run([str(prefix/'bin/savage-mod-player'),'--screenshot',str(work/'restarted.png'),
                        '--capture-delay','400'],env=env,capture_output=True,check=True,timeout=10)
        assert (work/'restarted.png').is_file() and preserved.read_bytes()==b'preserve user data'
        print('Installed launcher restarts the new version with preserved user data: OK')


if __name__=='__main__': main()
