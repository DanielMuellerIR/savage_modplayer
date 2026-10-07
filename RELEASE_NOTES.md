Savage Mod Player 1.6.29 also drains the final macOS audio buffer when a valid
HAL timestamp is already in the past. The deadline starts no earlier than the
finished rendering of the buffer, while future presentation times and explicit Stop
keep their behavior. A deterministic regression covers stale, future and missing
timestamps; GitHub CI exposed the stale-timestamp case.

iOS watchdog tests now separate deterministic timeout/cancellation decisions
from asynchronous worker start and stop, avoiding unobserved scheduling assumptions.

Savage Mod Player 1.6.28 fixes issues found in a full source review:
concurrent audio sink start/stop, delayed notes, IT combined portamento and
modern tempo changes, short explicit sample loops, corrupt S3M PCM headers,
and oversized numeric IT extensions. macOS media commands safely reach the
main actor, and sample export keeps the selected song across playlist changes.
Nested playlist archives share extraction limits; hidden archive music is
included. Library deletion reports failures and preserves the remaining index.
Browser VU meters clear on Stop. Release and smoke-test scripts now
protect their destination, tags, processes and saved preferences.

Savage Mod Player 1.6.27 adds a Linux x86_64 AppImage built with pinned
appimagetool 1.9.1 and a verified runtime. It packages the terminal player
with its Swift runtime, icon, documentation and licenses.
Explicit CLI help now succeeds with exit code 0.

Savage Mod Player 1.6.26 adds MPRIS2 media controls to Linux CLI playback,
using libdbus-1. Desktop controls can pause/resume, stop/restart, change tracks
and volume, and read the title and position. No Linux GUI is added.

Savage Mod Player 1.6.25 follows the original Impulse Tracker 2.14 ping-pong
loop endpoints, including fractional sample steps. Two synthetic reference
renders exposed a longer loop period in the previous renderer.

Savage Mod Player 1.6.24 prepares the ProTracker vibrato/tremolo table when
creating playback channels, keeping its first initialization off the audio thread
in debug builds. Table values and audio output are unchanged.

Savage Mod Player 1.6.23 lets macOS CLI playback drain its final audio buffer
before reporting the natural end. An explicit Stop still interrupts playback.
The renderer and audio samples are unchanged.

Savage Mod Player 1.6.22 narrows the falling-note window when **Tonumfang** is
selected, keeping keys and note bars exactly as wide as in the full keyboard.
**Klaviatur** restores the previous window width, including a custom size.
The controls move below the title in narrow windows.

Savage Mod Player 1.6.21 defaults the falling-note window to an 88-key keyboard
from A0 to C8, extending it automatically for tracker notes outside that range.
Choose **Tonumfang** to zoom to the song or **Klaviatur** to return to the full
keyboard; the selection is remembered. Keys retain slender proportions when
zoomed, bars are narrower and key highlights are softer. Note names appear
horizontally or rotated inside bars when space permits; hovering still shows
the note, channel and duration.

Savage Mod Player 1.6.20 adds a separate macOS piano-roll window. Open **View
(Darstellung) → Notenregen öffnen** or press **Shift–Command–N**: upcoming tracker
notes fall towards a keyboard, labelled with their note names and coloured by
channel. Choose a two-, four-, or eight-second lookahead. Keys light up while
voices sound; mute and solo are respected. Pause, seek, tempo changes, pattern
loops and overlapping IT voices follow the same sequencer as audio playback.
The preview runs in the background only while its window is open.

Bars show triggered tracker notes and sounding voice durations. Sample contents
are not transcribed into notes, and pitch slides/vibrato do not move the bars.
After a manual seek or tempo change, the preview briefly recalculates.
The app packager now asks Swift for its binary directory, so builds with the
new Swift build system also package the freshly compiled executable.

Savage Mod Player 1.6.19 keeps forward Bxx/Dxx jumps within the current MOD order
playing until the actual song end. Delayed desktop and browser drops respect Stop
and newer selections. Browser Worklet messages carry their playback identity, so
late end events cannot restart playback or skip the newly selected track.

Savage Mod Player 1.6.18 fixes malformed IT resource exhaustion, unsafe library
symlink destinations, ping-pong playback, IT order jumps and stereo sample export.
Pending loads respect pause and newer selections; favorite queues update immediately.
The desktop tracker refreshes when changing modules. The web player resets voices
between tracks, preserves finite pattern loops and uses the selected file for playlist
navigation. Quick Look refreshes cached audio after upgrades. Linux desktop entries
use the installed executable path, and DMG cleanup only detaches its own mount.
The DMG builder reads the actual mount location and waits for Finder before setting
the installation layout. The window leaves room for Finder’s tab and path bars.

The reference comparison retains stereo energy and rejects misleading lag matches
with only two overlapping envelope values.

Savage Mod Player 1.6.17 shows up to eight channel scopes per row on wide iPads. Scope height uses the actual playback column width.

Savage Mod Player 1.6.16 uses the available height of the iPad playback column
for the master and channel oscilloscopes. iPhone sizing stays unchanged;
modules with many channels remain scrollable. The DMG builder also verifies
that Finder retains the intended window size and places icons above the
background labels.

Savage Mod Player 1.6.15 is a correctness release. It preserves rapid tempo
changes, reports incomplete library scans and imports honestly, and rejects
special files before the CLI can block on them.

## Playback

- BPM and speed changes now travel through independent atomic requests. A
  later change can no longer carry a stale value for the other control, and
  the UI keeps each requested value until the audio callback has published its
  acknowledgement. A late acknowledgement from an older audio block also
  cannot revive a tempo request that a seek has already superseded.
- The visualizer consumes each audio-block peak once. Faster UI polling keeps
  the latest waveform visible without applying the same VU attack repeatedly.

## Files and command line

- A failed file-type lookup makes a library scan incomplete instead of
  silently removing a known, still existing track. Recursive imports report
  the affected relative path instead of dropping the child without a trace.
  A module that cannot be read for fingerprinting likewise makes the scan
  explicitly incomplete instead of hiding a stale index entry behind success.
- A cancellation raised while a coordinated iCloud or File Provider read is
  hashing or copying data is reported as cancellation when that step returns.
- Direct CLI inputs are opened non-blocking and checked with `fstat` before
  reading. A named pipe such as `stream.mod` now fails immediately in analysis
  and live-playback modes instead of waiting forever for a writer.

## Build and verification

- The visualizer CPU measurement distinguishes a missing preferences domain
  from a failed backup. It aborts before changing preferences when backup
  fails, preserves a backup when restore fails, and only stops the process it
  started itself.
- The Linux static build handles rootless and user-namespace Docker modes
  explicitly, no longer hides ownership failures, and verifies every `.build`
  artifact from the host after the container exits.
- Automated regression coverage now includes playback, library, import, iOS,
  CLI, build-script, Linux-build logic, and browser paths.
