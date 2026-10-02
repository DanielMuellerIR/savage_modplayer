// Regressionen fuer Titelwechsel, asynchronen Stop und echte Song-Endereignisse.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ModPlayer, parseModBuffer } from '../../modplayer.js';

const source = readFileSync(new URL('../../mod-player-worklet.js', import.meta.url), 'utf8');
class Processor {
  constructor() { this.messages = []; this.port = { postMessage: m => this.messages.push(m) }; }
}
let Worklet;
new Function('AudioWorkletProcessor', 'registerProcessor', source)(Processor, (_, type) => { Worklet = type; });
function module() {
  const bytes = new Uint8Array(2108);
  bytes[950] = 1;
  bytes.set([77, 46, 75, 46], 1080);
  return parseModBuffer(bytes.buffer, 'synthetic.mod');
}
const mod = module();
const worklet = new Worklet();
worklet.play(mod, 8000);
worklet.channels[0].playing = true;
worklet.channels[0].instrument = { pcm: [1, 1], length: 2 };
worklet.patternDelay = 4;
worklet.patternDelayCounter = 2;
worklet.positionJump = 9;
worklet.play(mod, 8000);
worklet.publishRow = true;
worklet.nextRow();
assert.equal(worklet.channels[0].playing, false, 'Neuer Titel darf keine alte Stimme erben');
assert.equal(worklet.patternDelayCounter, 0);
assert.equal(worklet.position, 0);
assert.equal(worklet.messages.at(-1).songEnded, false);
worklet.rowIndex = 63;
worklet.patternLoopRow = 0;
worklet.nextRow();
assert.equal(worklet.messages.at(-1).songEnded, false, 'E6-Loop ist kein Songende');
worklet.rowIndex = 63;
worklet.nextRow();
assert.equal(worklet.messages.at(-1).songEnded, true, 'Natuerlicher Ein-Order-Wrap ist Songende');
worklet.rowIndex = 0;
worklet.positionJump = 0;
worklet.patternBreak = 2;
worklet.nextRow();
assert.equal(worklet.position, 0);
assert.equal(worklet.rowIndex, 2, 'B00+D02 darf nicht in die naechste Order springen');
assert.equal(worklet.messages.at(-1).songEnded, false, 'Vorwaertssprung innerhalb der Order ist kein Songende');

const player = new ModPlayer();
const messages = [];
let finishSetup;
player.mod = mod;
player.setupAudio = () => new Promise(resolve => { finishSetup = () => {
  player.worklet = { port: { postMessage: m => messages.push(m) } };
  player.audio = { sampleRate: 8000 };
  resolve();
}; });
player.resumeContext = () => {};
player.tryResumeContext = async () => {};
const pending = player.play();
player.stop();
finishSetup();
assert.equal(await pending, false);
assert.equal(player.playing, false);
assert.equal(messages.some(m => m.type === 'play'), false, 'Stop muss wartenden Start entwerten');
player.setupAudio = async () => {};
let finishResume;
player.tryResumeContext = () => new Promise(resolve => { finishResume = resolve; });
const suspended = player.play();
await Promise.resolve();
player.stop();
finishResume();
assert.equal(await suspended, false, 'Stop gilt auch waehrend Audio-Resume');
console.log('Wiedergabezustand: alle Regressionen bestanden.');

// Der echte UI-Ladepfad laeuft mit kleinen DOM-Ersatzobjekten; die Dateileser
// bleiben steuerbar, damit die Reihenfolge unabhaengig vom Rechner reproduziert wird.
const appSource = readFileSync(new URL('../../src/app.js', import.meta.url), 'utf8');
const loadSource = appSource.slice(appSource.indexOf('async function loadFile('), appSource.indexOf('// HTML-Escaping'));
const clickSource = appSource.slice(appSource.indexOf("playBtn.addEventListener('click'"), appSource.indexOf('// Drag/Klick auf der Timeline'));
const createUI = new Function('parseModBuffer', `
  let currentMod = null, currentFile = null, currentPosition = 0, lastPosition = 0, currentRow = 0;
  let loadRevision = 0, playRequested = false;
  const modList = [], WORKLET_BLOB_URL = 'test';
  const titleEl = {}, statusName = {}, statusFile = {}, positionScrubber = {};
  const playBtn = { addEventListener(_, fn) { this.click = fn; } };
  let selectedFile = null, playingUI = false, error = null;
  const player = {
    playing: false, mod: null, stop() { this.playing = false; },
    setMod(mod) { this.mod = mod; },
    prepareAudioForGesture: async () => {}, resumeContext() {},
    play: async function() { this.playing = true; return true; }, setPosition() {}
  };
  function setUpPlayerCallbacks() {}
  function renderInstruments() {}
  function renderPattern() {}
  function syncModSelectSelection(file) { selectedFile = file; }
  function setPlayingUI(playing) { playingUI = playing; }
  function showError(message) { error = message; }
  ${loadSource}
  ${clickSource}
  return { loadFile, modList, playBtn, player, state: () => ({currentFile, selectedFile, playingUI, error}) };
`);
const ui = createUI(parseModBuffer);
const fileData = new Uint8Array(2108); fileData[950] = 1; fileData.set([77,46,75,46], 1080);
let finishRead;
const older = { name: 'same.mod', size: 2108, arrayBuffer: () => new Promise(resolve => { finishRead = resolve; }) };
const newer = { name: 'same.mod', size: 2110, arrayBuffer: async () => fileData.buffer };
ui.modList.push({ name: older.name, file: older }, { name: newer.name, file: newer });
const oldLoad = ui.loadFile(older);
await ui.loadFile(newer);
finishRead(fileData.buffer);
await oldLoad;
assert.equal(ui.state().currentFile, newer, 'Spaeter beendetes Lesen darf neuere Auswahl nicht ersetzen');
assert.equal(ui.state().selectedFile, newer, 'Gleicher Dateiname darf keine andere Datei markieren');
let finishAudio;
const waitingAudio = new Promise(resolve => { finishAudio = resolve; });
const waitingLoad = ui.loadFile(newer, { audioReady: waitingAudio });
await Promise.resolve();
await ui.playBtn.click();
finishAudio();
await waitingLoad;
assert.equal(ui.player.playing, false, 'UI-Stop entwertet wartendes Autoplay');
assert.equal(ui.state().playingUI, false);
console.log('UI-Ladepfad: Reihenfolge, Dateiidentitaet und Stop bestanden.');

const previousWindow = globalThis.window;
const previousNode = globalThis.AudioWorkletNode;
try {
  globalThis.window = { location: { href: 'http://localhost/' } };
  globalThis.AudioWorkletNode = class {
    constructor() { this.port = { postMessage() {} }; }
    connect(gain) { return gain; }
  };
  const gainPlayer = new ModPlayer();
  gainPlayer.audio = {
    state: 'running', destination: {}, audioWorklet: { addModule: async () => {} },
    createBuffer() { return {}; },
    createBufferSource() { return { connect() {}, start() {} }; },
    createGain() { return { gain: { value: 1 }, connect() {} }; }
  };
  gainPlayer.setVolume(0.3);
  await gainPlayer.setupAudio();
  assert.equal(gainPlayer.gain.gain.value, 0.09, 'Erster Graph nutzt dieselbe Lautstaerkekurve wie spaetere Aenderungen');
} finally {
  globalThis.window = previousWindow;
  globalThis.AudioWorkletNode = previousNode;
}
console.log('Audio-Graph: initialer Lautstaerkepegel bestanden.');
