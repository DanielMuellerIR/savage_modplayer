## 1.5.27 — 2026-07-11

- Replaced broad IT/OpenMPT warnings with a structured capability report. `cwtv` now identifies the creating tracker, `cmwt` controls format compatibility, and full OpenMPT versions come from their dedicated extension fields. A newer OpenMPT creator version no longer warns by itself.
- XTPM, STPM, legacy ModPlug chunks, MIDI/plugin routing, and all current OpenMPT `PlayBehaviour` bits are parsed at their structural boundaries. Marker bytes inside patterns or compressed/uncompressed PCM can no longer be mistaken for extensions.
- Known channel, timing, mix, preamp, restart, filter, and PCM compatibility values are applied by the engine. Classic, alternative, and modern OpenMPT tempo modes are supported, as are extended IT patterns from 1 to 1,024 rows.
- Warnings now require actual use in the played order path. Dormant MIDI flags, default macros, unused plugin definitions, metadata, and unsupported properties of unused instruments remain silent; used external routes identify the instrument, channel, or plugin slot.
- Fixed extended-pattern startup and deleted order references. Patterns longer than 64 rows no longer play their tail and then restart from row zero, and references to deleted patterns are skipped like OpenMPT.
- Offline rendering now trims the final block at the exact sequencer end frame. The UI duration uses the same jump/loop/delay/tempo-aware sequencer probe instead of a static row estimate; the primary OpenMPT reference now shows and renders exactly 46.080 seconds.
- `savage-cli --info` now reports tracker identity, `cwtv`/`cmwt`, full OpenMPT versions, every structured extension chunk, `PlayBehaviour` state, and concrete capability results.
- Added deterministic OpenMPT-extension, warning, compatibility-bit, variable-pattern, and MIDI/plugin fixtures. The reproducible A/B report now includes declared duration and distinguishes OpenMPT's terminal WAV padding from musical duration.

### Deliberate boundaries

- Savage Mod Player remains a native PCM tracker engine, not a VST/AudioUnit host or external MIDI renderer. Those paths warn only when triggered.
- Deprecated pre-1.17 OpenMPT swing, the superseded old loop/jump rule, imprecise legacy ping-pong overshoot, and proprietary envelope release nodes remain feature-specific compatibility limits.

## 1.5.25 — 2026-07-11

- The header now shows the number of pattern channels actually used by the song, before BPM.
- PAL/NTSC moved next to the master oscilloscope and is available only for Paula-based MOD formats.
- Quick Look now renders and caches a fast 60-second audio preview; unsupported files show a readable error instead of an endless loading indicator.

The macOS app now plays **Impulse Tracker modules (`.it`)** in sample and instrument mode. The new engine covers native IT 2.14/2.15 playback from parsing through real-time audio, CLI rendering, drag & drop, and Quick Look.

## Added

- **Impulse Tracker (`.it`) support**: up to 64 logical channels, a preallocated 256-voice NNA pool, NNA/DCT/DCA, 120-note sample maps, envelopes, fadeout, sustain loops, stereo samples, surround, sample vibrato, pitch-pan, volume/pan swing, and resonant per-voice filters.
- **IT 2.14/2.15 samples**: uncompressed and compressed 8-/16-bit mono or stereo PCM, signed/unsigned and delta variants, forward and ping-pong loops, and separate sustain loops.
- **IT effect semantics**: effect and volume-column memory, `Old Effects`, `Compatible Gxx`, pattern/row delays and loops, tempo/global/channel volume, retrigger, tremor, vibrato, panbrello, and common filter macros.
- **Public integration**: `.it` works in the loader, playlist scanner, file dialog, drag & drop, Finder “Open with”, `savage-cli`, and the bundled Quick Look extension. The app shows an Impulse Tracker format badge and renders all pattern rows and up to 64 channels.
- **Compatibility reporting**: unsupported MIDI/plugin routing, limited custom MIDI macros, newer tracker versions, and unknown MPTM/IT extensions produce visible non-fatal warnings.

## Verification

- The full Swift suite, dedicated filter/NNA/stereo fixtures, a 64-channel/256-voice release stress test, JS↔Swift MOD parity, the signed app build, and the Quick Look extension pass.
- Playback was compared against the pinned `openmpt123`/libopenmpt reference and, for filter and compatibility details, the OpenMPT and Schism Tracker source implementations.

## Known limitations

- MPTM, proprietary OpenMPT extensions, VST/plugin playback, and external MIDI output are not supported.
- Embedded MIDI macros are limited to common cutoff/resonance filter macros.
- Pattern lengths from 32 through 200 rows are supported; shorter or longer extension patterns are rejected with a parser error.
- The HTML5 player remains intentionally limited to classic 4-channel ProTracker MOD files.

## Notes

- The DMG is signed and notarized and includes the app and Quick Look extension; no module files are bundled.
