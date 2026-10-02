Savage Mod Player 1.6.18 fixes malformed IT resource exhaustion, unsafe library
symlink destinations, ping-pong playback, IT order jumps and stereo sample export.
Pending loads respect pause and newer selections; favorite queues update immediately.
The desktop tracker refreshes when changing modules. The web player resets voices
between tracks, preserves finite pattern loops and uses the selected file for playlist
navigation. Quick Look refreshes cached audio after upgrades. Linux desktop entries
use the installed executable path, and DMG cleanup only detaches its own mount.

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
