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
const dropSource = appSource.slice(appSource.indexOf("window.addEventListener('drop'"), appSource.indexOf('// Sammelt alle Files'));
const callbackSource = appSource.slice(appSource.indexOf('function setUpPlayerCallbacks()'), appSource.indexOf('function renderInstruments()'));
const createUI = new Function('parseModBuffer', `
  let currentMod = null, currentFile = null, currentPosition = 0, currentRow = 0;
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
  const window = { addEventListener(_, fn) { this.drop = fn; } };
  const playerEl = { classList: { remove() {} } };
  let dragDepth = 0;
  async function collectDroppedFiles(dt) { return dt.collect(); }
  function isModName(name) { return name.endsWith('.mod'); }
  function addMods(files) { for (const file of files) modList.push({name: file.name, file}); }
  let playerCallbacksConfigured = false;
  const playlistMode = { checked: true }, statusRow = {}, posDisplay = {}, statusBpm = {}, statusSpeed = {};
  const vuTargets = [0, 0, 0, 0];
  player.watchRows = fn => { player.rowCallback = fn; };
  player.watchLevels = () => {};
  player.watchStop = () => {};
  function updateActiveRow() {}
  ${callbackSource}
  function renderInstruments() {}
  function renderPattern() {}
  function syncModSelectSelection(file) { selectedFile = file; }
  function setPlayingUI(playing) { playingUI = playing; }
  function showError(message) { error = message; }
  ${loadSource}
  ${clickSource}
  ${dropSource}
  return { drop: window.drop, loadFile, modList, playBtn, player, state: () => ({currentFile, selectedFile, playingUI, error}) };
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


// Die Auftragsrevision muss schon während der Verzeichnis-/Provider-Sammlung gelten.
let finishCollection;
const delayedDrop = ui.drop({ preventDefault() {}, dataTransfer: {
  collect: () => new Promise(resolve => { finishCollection = resolve; }), files: []
} });
await ui.loadFile(newer);
finishCollection([older]);
await delayedDrop;
assert.equal(ui.state().currentFile, newer, 'Alter Drop darf neuere Dateiauswahl nicht ersetzen');
let rejectCollection;
const stoppedDrop = ui.drop({ preventDefault() {}, dataTransfer: {
  collect: () => new Promise((_, reject) => { rejectCollection = reject; }), files: [older]
} });
await ui.playBtn.click();
rejectCollection(new Error('Provider fehlgeschlagen'));
await stoppedDrop;
assert.equal(ui.player.playing, false, 'Stop muss auch den Drop-Fallback entwerten');
assert.equal(ui.state().currentFile, newer);

const transport = new ModPlayer();
transport.mod = mod;
transport.worklet = { port: { postMessage() {} } };
transport.audio = { sampleRate: 8000 };
transport.setupAudio = async () => {};
transport.resumeContext = () => {};
transport.tryResumeContext = async () => {};
let delivered = 0;
transport.watchRows(() => ++delivered);
await transport.play();
const oldRevision = transport.playRevision;
transport.stop();
transport.onMessage({data: {type: 'row', playRevision: oldRevision, songEnded: true}});
assert.equal(delivered, 0, 'Nach Stop eintreffendes Songende darf nicht ausliefern');
await transport.play();
transport.onMessage({data: {type: 'row', playRevision: oldRevision, songEnded: true}});
assert.equal(delivered, 0, 'Altes Songende darf den neu gestarteten Titel nicht überspringen');
transport.onMessage({data: {type: 'row', playRevision: transport.playRevision, songEnded: true}});
assert.equal(delivered, 1, 'Aktuelles Songende wird weiterhin ausgeliefert');
worklet.onmessage({data: {type: 'play', mod, sampleRate: 8000, playRevision: 77}});
worklet.nextRow();
assert.equal(worklet.messages.at(-1).playRevision, 77, 'Worklet muss die Startidentität zurückgeben');
console.log('Drop-Aufträge und veraltete Worklet-Ereignisse: Regressionen bestanden.');

const third = {name: 'next.mod', size: 2108, arrayBuffer: async () => fileData.buffer};
ui.modList.push({name: third.name, file: third});
await ui.loadFile(newer);
ui.player.rowCallback(0, 63, 125, 6, true);
for (let tick = 0; tick < 10; tick++) await Promise.resolve();
assert.equal(ui.state().currentFile, third, 'Aktuelles Songende muss Auto-Next weiterhin starten');
assert.equal(ui.player.playing, true);
console.log('UI-Songende: Auto-Next bleibt nach erfolgreichem Start aktiv.');
