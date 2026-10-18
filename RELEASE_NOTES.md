Savage Mod Player 1.6.53 reduces repeated object accesses in the shared sample renderer. Sample position and loop direction are calculated locally; voice gain and panning are refreshed at tracker ticks, block starts, seeks and A/B restarts. This keeps Swift’s safety checks, loop formulas and the strict 64-channel/256-voice real-time limit unchanged. The stress test also compares every PCM sample between the live and offline paths. Regression checks verify volume and panning changes at their exact tracker frames across different callback sizes.

Savage Mod Player 1.6.52 adds explicit CloudKit build configuration for Mac and iPhone. Opt-in builds validate the provisioning profile, app identifier, container, environment, expiry and local signing key before enabling the provider. Default builds keep cloud access disabled. Development and production remain separate; iOS builds use existing profiles without creating signing assets automatically. The real development round trip Mac → iPhone → Mac passes for playlists, favorites, song markers and sound overrides, including stable IDs and a Mac restart. The reviewed CloudKit schema is deployed to production, and the notarized configured Mac build passes native checks without an iCloud account, including retry, protected local storage, file exchange and song markers after restart. The real production round trip and explicit two-device conflicts with marker deletion pass; a Mac restart preserves the resolved state. An additional production check transfers a 6.4 MB asset containing 20,000 synthetic track descriptions and rejects an actual stale conditional write; the temporary validation zone is removed and the app snapshot remains unchanged. Actual network disconnection, account switching, service throttling and large two-device UI collections remain outside these checks. First-time setup now recognizes an absent private zone; only explicit confirmation creates it, while an established checkpoint still fails closed when cloud state is missing. Strict performance gates pass on controlled macOS and Linux hosts. Shared CI runners can exceed the 64-channel/256-voice render and 20,000-track setup timing limits; those thresholds remain unchanged and the runner discrepancy is tracked separately.

Savage Mod Player 1.6.51 adds the local app integration for metadata synchronization on Mac and iPhone/iPad: setup, status, track mapping, explicit conflict decisions and retry. A durable observed state preserves accepted choices across interrupted publication and restarts; playlists, markers, sound overrides, sync state and selected preferences share one recovery transaction. Missing stores or lost preference keys cannot become cloud deletions. Global track IDs, account generations and conditional writes protect local edits and late results. The actual CloudKit provider remains disabled pending verified container configuration, entitlements, profiles and a real two-device service test. Manual collection transfer remains available. Local song markers retain subsecond timestamps while keeping older files readable.

Savage Mod Player 1.6.50 adds native note-rain video export on macOS. A paused preview uses the same renderer as the final MOV. Choose resolution up to Full HD, 24/25/30/60 fps, high or compact H.264 compression, appearance, lookahead and a duration limit. The title and sound options are captured when opening the dialog; rendering runs in the background with progress and cancellation. Existing destinations are protected, and a finished video can be shown in Finder. Fixes a crash when opening the video preview in standalone app bundles. Export dialog buttons remain readable at the largest text size.

Savage Mod Player 1.6.49 adds the offline note-rain video renderer to the macOS core. H.264 video and lossless stereo Float32 audio share an integer sample clock; the final image is trimmed to the exact audio end. Rendering uses bounded audio, pixel and note buffers, preserves sound options and logical IT channel ownership, supports cancellation, and publishes a new MOV file only after successful completion. The native export interface follows separately.

Savage Mod Player 1.6.48 adds native collection export and import on macOS and iPhone/iPad. A preview shows playlists, favorites, song markers and sound settings; users review local track matches, map or skip missing tracks and decide conflicts before importing. The versioned `.savagecollection` file carries metadata without music or local URLs. A recovery journal protects the collection and its preferences across interrupted imports. Volume, running timers and the playback queue stay local. Manual queue advancement also preserves the next entry if playback cannot start at sleep-timer expiry. Multi-line Mac mapping rows keep path hints and match status readable.

Savage Mod Player 1.6.47 adds the shared portable collection format for playlists, favorites, song markers and global/per-track sound settings. Versioned JSON carries file-relative hints and optional content fingerprints, with bounded reads and validated references. Import previews require track mapping and explicit conflict decisions, preserve local data and reject stale previews. The format contains no audio or local source URLs; native import/export controls are a separate upcoming step.

Savage Mod Player 1.6.46 adds per-track sound settings to the macOS and iPhone/iPad apps. Explicit overrides for MOD clock, stereo separation, interpolation and the LED output filter each replace only their matching global default. Stable source IDs preserve settings across track changes and restarts; resetting affects only the selected track. Clock controls are hidden for XM, S3M and IT, where they do not apply. Damaged settings files are preserved while safe global defaults remain in use.

Savage Mod Player 1.6.45 adds a sleep timer to the macOS and iPhone/iPad apps. The last ten seconds fade out independently of interface updates. Cancellation and extension restore the desired volume smoothly; expiry stops playback and prevents automatic interruption resume or late loading from restarting it. The countdown continues across pauses, tracks and A/B playback. The volume setting is preserved, and an active timer is not restored after restarting the app.

Savage Mod Player 1.6.44 adds batch WAV export on macOS. Select tracks from the current playlist or search results, choose stereo mixes or channel stems, and reuse saved audio settings. Existing destinations can be skipped or retained under a new name. Progress, cancellation and a batch report with per-track results keep completed outputs visible; files are rendered sequentially with bounded audio buffers.

Savage Mod Player 1.6.43 adds export of played stereo channel stems on macOS. IT background voices remain assigned to their logical channel. Float32 WAV stems and the reference mix share their start, length and gain. A manifest records audio options and master processing limits: stems are captured before the tanh limiter; mixer volume and the external LED output filter are excluded. Two streaming render passes keep memory bounded. The interface provides progress and cancellation while preserving existing destination folders.

Savage Mod Player 1.6.42 adds native A/B playback from the song-marker view.
A bounded background render reconstructs the actual route to A, including
running samples, effect memory and IT background voices. Every repeat restores
that state and includes all ticks and delays of B. Cancellation, unreachable
boundaries, pause and settings changes have explicit states. The Mac note rain
uses the same snapshot and frame interval. The LED output filter continues to
process the resulting stream; its output history is outside the replay snapshot.
The sample and module inspectors receive their captured module when opening,
preventing an empty sheet on the first invocation.

Savage Mod Player 1.6.41 fixes playlist and queue transitions. Queued Mac
tracks preserve the original list; interrupted iOS loads preserve pending
entries and the resume anchor. Tracks added during a failed load keep their
priority. Saved playlists can reopen more than 128 independent archives while
sharing extraction size limits; safety limits are reported separately from
missing sources. Native drop and queue regression checks cover these cases.

Savage Mod Player 1.6.40 adds named song markers on Mac, iPhone and iPad.
Position and row survive restarts for each original source, including repeated
patterns. Targets can be edited, deleted and opened using the existing row jump.
A separate visual section selection highlights the Mac tracker and note-rain
position strip. Missing targets and damaged storage files are preserved; music
files are not changed. The selected playback loop mode remains independent.

Savage Mod Player 1.6.39 adds a module/instrument inspector on Mac, iPhone
and iPad. It shows structure, explicit source metadata, envelopes with loop,
sustain and carry, and existing IT compatibility diagnostics. The effect guide
distinguishes formats and columns, preserves zero parameters and explains
recognized ignored commands. Static counts do not represent playback events.
Both inspectors are available in the player’s info menu on iPhone/iPad.

Savage Mod Player 1.6.38 adds a sample inspector on Mac, iPhone and iPad.
It shows zoomable waveforms, both stereo channels, normal/sustain loops and
their direction. All instrument samples and the global IT sample pool remain
accessible; stored XM/IT keyboard mappings show transposition and unassigned
keys. Inspection reads existing data and preserves the instrument preview.
Dialog keys operate the sheet instead of the transport.

Savage Mod Player 1.6.37 adds metadata search, sorting and saved filters on Mac,
iPhone and iPad. Search finds internal titles and instrument names as well as
filenames and folders. Format, channel count, favorites, unheard tracks and recent
additions can be combined. Playback keeps the explicitly selected display order;
changing the display does not replace that selection. Actual playback records a
stable heard status, while loading or restoring a paused track does not. Collection
hints distinguish matching filenames from identical content and show indexing errors.

Savage Mod Player 1.6.36 adds a shared background metadata index for upcoming
library search and sorting. It records module titles, formats, channel and
instrument/sample counts, names and bounded playback durations. Unchanged files
reuse a versioned cache; missing, invalid and oversized files have individual
states. Cancellation keeps partial progress. Cache/file limits and nonblocking
regular-file checks protect indexing from oversized data and named pipes.

Savage Mod Player 1.6.35 brings saved playlists and a session queue to iPhone
and iPad. Playlists support creation, renaming, deletion and track reordering;
relative library references survive changes to the app container. Missing tracks
remain recorded. Track context menus add to playlists or play next; the queue
resumes the previous selection and preserves stopped playback. Search results
can explicitly become the playback selection. New controls are localized in
German and English.

Savage Mod Player 1.6.34 adds named playlists to the macOS sidebar. Lists retain
their order and original file/archive sources across restarts; missing sources
remain recorded. Track menus add to saved lists or to a session queue, which
can be reordered and resumes the previous list after queued tracks. Search
results can explicitly become the playback selection. Favorites now use source
IDs; migration keeps unseen legacy names pending and leaves ambiguous names unassigned.

Savage Mod Player 1.6.33 introduces a versioned store for named playlists and
source-based track references. References survive temporary copies and nested
archive extraction; same-named files in different folders stay distinct.
Missing sources remain recorded, and invalid playlist data is rejected without
replacing the saved collection. The macOS interface follows in the next update.

Savage Mod Player 1.6.32 adds Sparkle updates to the macOS app, with a manual
check in the app menu and automatic checks controlled in Settings. Installation
requires confirmation; update archives and the feed are signed. Existing versions
need one manual DMG installation. The release workflow prepares the signed feed
for GitHub Pages; its initial setup is documented in `docs/sparkle-release.md`.

Savage Mod Player 1.6.31 cancels pending file imports when system Play or Pause
is used. The browser player also offers Stop during its first folder import,
before a module has finished loading.

Savage Mod Player 1.6.30 keeps browser transport controls connected to the active
audio graph when URL loads overlap initial audio setup. The note window routes
Play/Pause and Stop through the main transport, cancelling pending file imports.
Stereo and interpolation changes retain the note preview without recalculating
it. Linux release uploads now find the AppImage and checksum at the builder's
default path. An unreachable ALSA self-stop branch was removed.

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
