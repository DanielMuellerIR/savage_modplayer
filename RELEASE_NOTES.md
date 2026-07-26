Savage Mod Player 1.6.0 adds a native iPhone app that plays MOD, S3M, XM, and IT
files on the same Swift replay engine as the macOS app, keeps playing while the
screen is locked, and can take in whole collection folders at once.

## iPhone app

- A native SwiftUI app for iPhone lives in `ios/` and links the same
  `SavageModPlayerCore` as the macOS app, the Quick Look extension, and the
  command line renderer. There is no second replay implementation.
- Playback continues in the background and while the device is locked. Title,
  format, folder, artwork, and elapsed time appear on the lock screen; play,
  pause, next, previous, the position scrubber, and the −15 s / +30 s buttons
  work from there and from headphone controls.
- The audio session handles the situations a phone actually runs into: an
  incoming call pauses and resumes, unplugging headphones pauses instead of
  switching to the speaker, and a media services restart rebuilds the engine
  including the low-pass node used by the LED filter.
- The library is a real folder tree, not a flat list. Folders start collapsed,
  the path to the playing track expands automatically, and playback and shuffle
  run across all folders. Live search, favourites, loop modes, and session
  restore work as they do on the desktop.
- Visualizations are off by default. The common case on a phone is music playing
  with the screen dark, and nothing should be computed that nobody sees. Turning
  them on enables the master oscilloscope, VU meters, and a bounded number of
  per-channel scopes.
- PAL/NTSC clocking, the LED filter, hi-fi interpolation, and stereo separation
  are all available. Appearance follows the system by default and can be forced
  to light or dark. German and English are both supported.

## Getting music onto the device

- **Folder import in the app**: pick one folder and everything playable inside
  is copied into the library with its structure intact. Archives are unpacked,
  duplicates are skipped, progress is shown, and the import can be cancelled
  without leaving a half-written library behind. Files that live in a cloud file
  provider are downloaded and read through a file coordinator first.
- **Finder file sharing**: connect the iPhone, open Files in the Finder, and
  drag whole folders onto the app. The same library shows up in the iOS Files
  app under "On My iPhone". The app reconciles its index with the file system on
  every launch, so files added or deleted from outside are picked up.
- **Reset library**: a two-step confirmation clears tracks, index, and cached
  extracts; favourites can be kept.

## ZIP support without external tools

- A project-owned ZIP reader was added to the core. It streams each entry
  block-by-block straight into its target file, so memory use does not grow with
  archive size — a 120 MB archive now peaks at roughly 7 MB instead of 122 MB.
- Only playable module files are decompressed. In a large collection archive
  that saves most of the time and most of the space.
- Path traversal entries, symbolic links, encrypted entries, ZIP64 archives, and
  implausible compression ratios are rejected rather than sanitized, and every
  entry's CRC32 is verified.
- macOS and Linux continue to use the system `bsdtar`, which also reads 7-Zip
  archives. 7-Zip is not supported on iOS and is reported as such.

## Verification and known limits

- The release is covered by the full Swift suite, the Linux container build and
  test run, the macOS app and Quick Look build, byte-identical command line WAV
  output against the previous baseline across the local module corpus, and the
  iOS simulator build and test run.
- Background playback, lock screen control, headphone behaviour, and memory use
  while importing a large archive can only be confirmed on a physical device and
  are not claimed on the strength of a simulator run.
- The iPhone app has no WAV export; that stays a desktop feature.
- MPTM, VST/AudioUnit plug-in playback, and external MIDI output remain outside
  the native engine. The HTML5 player remains intentionally limited to classic
  four-channel ProTracker MOD files.
- The DMG is Developer ID-signed, notarized by Apple, and includes the app and
  Quick Look extension. No module files are bundled.
