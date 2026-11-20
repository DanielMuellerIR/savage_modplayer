window.__savageDebug = {
  getState() {
    return {
      currentMod: !!currentMod,
      playerPlaying: player.playing,
      audioState: player.audio?.state || null,
      hasWorklet: !!player.worklet,
      setupPending: !!player.setupPromise,
      callbacksConfigured: playerCallbacksConfigured
    };
  }
};

// ─── Browser-Regressionstest: Ordner-Drop muss Autoplay auslösen ─────────────
// Nur aktiv mit ?testDropAutoplay=1. Der Button liefert die echte User-Geste
// im selben Dokument; danach wird ein Ordner-Drop mit webkitGetAsEntry()
// simuliert und der sichtbare Player-Status geprüft.
if (new URLSearchParams(window.location.search).has('testDropAutoplay')) {
  const testButton = document.createElement('button');
  testButton.id = 'run-drop-autoplay-test';
  testButton.textContent = 'RUN DROP AUTOPLAY TEST';
  testButton.style.position = 'fixed';
  testButton.style.zIndex = '1000';
  testButton.style.top = '8px';
  testButton.style.left = '8px';

  const testResult = document.createElement('pre');
  testResult.id = 'drop-autoplay-test-result';
  testResult.style.position = 'fixed';
  testResult.style.zIndex = '1000';
  testResult.style.top = '40px';
  testResult.style.left = '8px';
  testResult.style.maxWidth = '520px';
  testResult.style.padding = '8px';
  testResult.style.background = 'white';
  testResult.style.color = 'black';
  testResult.textContent = 'idle';

  document.body.appendChild(testButton);
  document.body.appendChild(testResult);

  const testMod = new Uint8Array(1084 + 64 * 4 * 4);
  testMod[950] = 1;
  testMod.set(new TextEncoder().encode('M.K.'), 1080);
  const testFileName = 'smoke.mod';

  testButton.addEventListener('click', async () => {
    try {
      testResult.textContent = 'running';
      const file = new File([testMod], testFileName, { type: 'audio/mod' });
      const fileEntry = {
        isFile: true,
        isDirectory: false,
        file(success) { setTimeout(() => success(file), 0); }
      };
      const directoryEntry = {
        isFile: false,
        isDirectory: true,
        createReader() {
          let sent = false;
          return {
            readEntries(success) {
              setTimeout(() => {
                if (sent) success([]);
                else {
                  sent = true;
                  success([fileEntry]);
                }
              }, 0);
            }
          };
        }
      };
      const event = new Event('drop', { bubbles: true, cancelable: true });
      Object.defineProperty(event, 'dataTransfer', {
        value: {
          items: [{ webkitGetAsEntry: () => directoryEntry }],
          files: [],
          dropEffect: 'copy'
        }
      });
      window.dispatchEvent(event);
      const deadline = performance.now() + 5000;
      while ((!player.playing || statusFile.textContent !== testFileName) && performance.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 20));
      }

      const state = {
        status: statusState.textContent,
        playText: playBtn.textContent,
        footer: footerState.textContent,
        file: statusFile.textContent,
        row: statusRow.textContent,
        debug: window.__savageDebug.getState(),
        vu: vuBars.map(el => el?.style.height || '')
      };
      const ok = state.status === 'PLAYING' &&
        state.playText === 'STOP' &&
        state.file === testFileName &&
        state.debug.playerPlaying &&
        state.debug.hasWorklet;
      testResult.textContent = JSON.stringify({ ok, state }, null, 2);
    } catch (error) {
      testResult.textContent = `FAILED: ${error.message}`;
      console.error(error);
    }
  });
}
