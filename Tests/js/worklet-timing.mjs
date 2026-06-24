// Headless-Parität-Test für mod-player-worklet.js.
//
// Lädt die echte `Channel`-Klasse aus dem Worklet (ohne den AudioWorklet-
// Rahmen) und prüft dieselbe ProTracker-Tick-Timing-Regel wie der Swift-Test
// DSPChannelTimingTests: Porta-Slides (1xx/2xx/3xx) und der Vibrato-/Tremolo-
// Sinusindex schreiten NUR auf Ticks > 0 fort, nie auf Tick 0. Beide Varianten
// müssen sample-genau dieselben Werte liefern.
//
// Aufruf (headless): node Tests/js/worklet-timing.mjs  → Exit 0 = grün.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const workletPath = join(here, '..', '..', 'mod-player-worklet.js');

// Nur den Teil bis zur AudioWorkletProcessor-Klasse nehmen: das sind die
// Konstanten (PAULA_FREQUENCY etc.) plus die self-contained `Channel`-Klasse.
const src = readFileSync(workletPath, 'utf8');
const channelSrc = src.split('class ModPlayerWorklet')[0];
const Channel = new Function(channelSrc + '\nreturn Channel;')();

// Mini-Mock des Worklets: die Channel-Logik liest nur tick + sampleRate.
const worklet = { tick: 0, sampleRate: 44100 };

function makeChannel() {
    const ch = new Channel(worklet, 1);
    return ch;
}

// Eine komplette Row bei Speed 6 abspielen (Ticks 0..5).
function playRow(ch, ticksPerRow = 6) {
    for (let tick = 0; tick < ticksPerRow; ++tick) {
        worklet.tick = tick;
        ch.performTick();
    }
}

let failures = 0;
function check(name, actual, expected, eps = 1e-4) {
    if (Math.abs(actual - expected) > eps) {
        console.error(`✗ ${name}: erwartet ${expected}, war ${actual}`);
        failures++;
    } else {
        console.log(`✓ ${name}`);
    }
}

// 2xx Porta-Down: 5 Schritte/Row (Tick 1..5), nicht 6. delta=4 → +20 → 320.
{
    const ch = makeChannel();
    ch.period = 300;
    ch.currentPeriod = 300;
    ch.periodDelta = 4;
    ch.portamento = false;
    playRow(ch);
    check('slide-down: 5 Schritte/Row', ch.currentPeriod, 320);
}

// Tick 0 darf nicht sliden, Tick 1 schon.
{
    const ch = makeChannel();
    ch.period = 300;
    ch.currentPeriod = 300;
    ch.periodDelta = 4;
    ch.portamento = false;
    worklet.tick = 0; ch.performTick();
    check('slide: Tick 0 eingefroren', ch.currentPeriod, 300);
    worklet.tick = 1; ch.performTick();
    check('slide: Tick 1 erster Schritt', ch.currentPeriod, 304);
}

// 3xx Tone-Porta: 5 Schritte Richtung Ziel (Ziel weit genug weg).
{
    const ch = makeChannel();
    ch.period = 400;
    ch.currentPeriod = 300;
    ch.portamentoSpeed = 4;
    ch.periodDelta = 4;
    ch.portamento = true;
    playRow(ch);
    check('tone-porta: 5 Schritte/Row', ch.currentPeriod, 320);
}

// Vibrato-Index: 5 Advances/Row. speed=4 → 20, nicht 24.
{
    const ch = makeChannel();
    ch.period = 300;
    ch.currentPeriod = 300;
    ch.vibrato = true;
    ch.vibratoSpeed = 4;
    ch.vibratoDepth = 8;
    ch.vibratoIndex = 0;
    playRow(ch);
    check('vibrato-index: 5 Advances/Row', ch.vibratoIndex, 20);
}

// Vibrato-Index auf Tick 0 eingefroren.
{
    const ch = makeChannel();
    ch.period = 300;
    ch.currentPeriod = 300;
    ch.vibrato = true;
    ch.vibratoSpeed = 4;
    ch.vibratoIndex = 0;
    worklet.tick = 0; ch.performTick();
    check('vibrato: Tick 0 eingefroren', ch.vibratoIndex, 0);
}

// Tremolo-Index: gleiche Regel wie Vibrato.
{
    const ch = makeChannel();
    ch.volume = 32;
    ch.currentVolume = 32;
    ch.tremolo = true;
    ch.tremoloSpeed = 4;
    ch.tremoloDepth = 8;
    ch.tremoloIndex = 0;
    playRow(ch);
    check('tremolo-index: 5 Advances/Row', ch.tremoloIndex, 20);
}

if (failures > 0) {
    console.error(`\n${failures} Fehler — Worklet-Timing weicht ab.`);
    process.exit(1);
}
console.log('\nAlle Worklet-Timing-Checks grün (Parität zu DSPChannel.swift).');
