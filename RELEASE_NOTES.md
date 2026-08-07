Savage Mod Player 1.6.5 is a correctness and robustness release across all
targets: an audible XM tuning fix, stricter parsers and ZIP handling, a safer
library import, and small fixes in the iPhone app, the CLI, and the build
scripts.

## Playback correctness

- XM modules that use the Amiga frequency table now play at the pitch
  FastTracker II defines (frequency = 8363 × 1712 / period). They were
  previously computed against the Amiga PAL clock and sounded roughly two
  octaves too low. Modules using the linear frequency table are unaffected.
- An S3M header global volume of 0 is now honoured as a deliberately silent
  start. The single documented real-world exception stays: files written by
  Scream Tracker before 3.20 often store 0 for "unset" and keep full volume.
- In the track-loop mode of the iPhone app, the elapsed time shown in the app
  and on the lock screen resets at the loop point instead of overtaking the
  track duration. It now resets to the point playback actually continues from —
  for a backward Bxx jump that is the jump target, not the restart position
  from the module header. The lock screen shows the new time immediately
  instead of one display tick later.
- The instrument preview of XM modules is now tuned exactly like the same note
  in the played module. It previously used the MOD calculation (period 214
  against the Amiga clock) and was noticeably out of tune; both XM frequency
  modes are covered.

## Stricter parsing and ZIP handling

- The S3M parser validates the declared length of every packed pattern and
  rejects truncated patterns instead of silently reading sample data as note
  events.
- The XM parser rejects truncated headers and files, and treats pattern cells
  that would cross the declared pattern data as corruption. Pattern headers and
  pattern data must also lie completely inside the file, and non-empty pattern
  data must contain every declared cell — a truncated file no longer passes as
  a valid, partially silent module anywhere.
- The ZIP reader enforces its entry limit while parsing the central directory,
  cross-checks the directory against the end-of-central-directory record, and
  rejects entries that would hit the same target file — including names that
  collide only on case-insensitive file systems. Target files are created
  exclusively, never overwritten.
- The ZIP reader accepts the optional digital signature record at the end of
  the central directory (ZIP APPNOTE 6.3.10, section 4.3.13); standards
  compliant signed archives were previously rejected as corrupt. Invalid limits
  (such as a negative entry count) now raise a regular error instead of
  terminating the process.

## Library import

- A source archive is deleted only after a fully successful import: no
  cancellation, no errors, and at least one file taken over. Archives without
  playable content, partially imported archives, and entries skipped due to an
  unsupported compression method no longer make the original disappear.
- An archive inside an archive is now unpacked as well, up to three levels
  deep. Its content used to be dropped while the outer source archive counted
  as fully imported and was deleted — taking the last copy with it.
- Cancelling is recognised as such throughout the pipeline (including waiting
  for cloud files) and is no longer reported as file errors.
- Unreadable source folders are reported instead of silently skipped, an
  interrupted file-system scan no longer removes known entries from the index,
  and a partially failed library reset rebuilds the index from what actually
  remains on disk.
- A directory scan that cannot even start now counts as incomplete; it used to
  be read as an empty library and wiped the whole index. During a reset, a
  library root that cannot be listed is reported, the existing index is kept
  until a provably complete rebuild, and a failure in a temporary or cache
  directory no longer overrides the "delete index file" option.
- Unpacking archives on macOS and Linux (bsdtar) can now be cancelled.
- Archives whose name matches the Amiga `mod.` prefix (such as
  `mod.collection.zip`) are classified as archives everywhere and unpacked
  instead of being imported as an unplayable "module".

## Quick Look

- The preview cache key is derived from the exact bytes that were read and
  rendered. A file replaced in place — even with identical size and
  timestamp — can no longer serve the previous file's audio from the cache.

## CLI

- `--play` with `--seconds 0` now honours the documented 600-second cap
  instead of playing a loop forever.
- `--play` rejects `--out`, `--stdout`, `--normalize`, and `--rate` instead of
  silently ignoring them.
- `--play` also works with output devices above 192 kHz. Real-time output is
  streamed and needs no offline memory budget; the offline sample-rate ceiling
  used to end playback before the first sample.

## iPhone app

- "Previous" over a broken file now searches backwards instead of jumping
  forward to the current track again.
- A paused track keeps its position across a media services restart followed by
  an app relaunch.
- Errors and pending archives are also shown when the library is empty, so a
  failed unpack of the only ZIP is visible and can be retried.

## Build scripts and CI

- `release.sh`, `install.sh`, and `ios/scripts/build-device.sh` parse all
  arguments before doing anything: `--help` answers immediately and unknown
  options abort instead of triggering builds, notarisation, or installs.
- The notarisation helper cleans up its temporary directory on every failure
  path. A stale DMG is removed by `build_dmg.sh` before every build, so the
  success check in `release.sh` really verifies the current run.
- CI now also builds the app bundle including the Quick Look extension
  (unsigned), runs the UI source tests, and builds and tests the iPhone app
  against the simulator SDK.
