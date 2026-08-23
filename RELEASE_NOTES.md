Savage Mod Player 1.6.10 fixes launching the Mac app with a file argument,
completes the command line with playlist playback and keyboard control, and
makes the iPhone app smoother when loading tracks and opening external files.

## Mac app

- `Savage Mod Player <song.mod>` and `open --args <song.mod>` open a window again
  and play the given file. The cause was AppKit: a positional launch argument
  counted as "open this file" there, and SwiftUI does not create its window on
  that launch path. Without a window, the "Open With" path could not receive the
  file either — the app kept running invisibly. The same applied to a folder
  argument and to an argument that is not a path at all.
- A `-key value` pair appended by macOS at launch is skipped together with its
  value. A folder named `YES` in the working directory is no longer mistaken for
  the startup folder.
- Finder, Dock and "Open With" are unchanged: that path uses an Apple event, not
  the command line.
- The visualizer frame rate can be set to 30, 24, 15 or 10 Hz in Settings
  (Cmd+,). 30 Hz stays the default and keeps the full look. The effect is
  substantial: on a Mac with an M5 chip the same playback cost about 22 % of a core at 30 Hz,
  about 18 % at 15 Hz and about 14 % at 10 Hz. The change takes effect immediately; the compact window
  stays at 5 Hz regardless.

## iPhone app

- "Open With …" works. MOD, S3M, XM, IT and ZIP have always been registered as
  document types, but a handed-over file only launched the app and was then
  discarded. It is now imported into the library — unpacking an archive along
  the way — and played. A file arriving during the startup scan waits until the
  library is free.
- A track is no longer read on the main thread. Reading, parsing and measuring
  the playing time run in the background; only handing the module to the engine
  stays up front. A large module or a file from the cloud no longer freezes the
  interface.
- A new load request supersedes the previous one. Tapping "next" repeatedly no
  longer waits for every skipped track to be read in turn.
- The play queue keeps its selection. When playback was started from a search or
  from the favourites, a library change no longer replaces it with the whole
  collection — a single new favourite was enough to trigger that.
- Document type names appear in English on English devices. The Files app, the
  share sheet and "Open With …" showed German everywhere.
- The audio session is managed by the app alone. The player core used to set it
  a second time at startup, with a console message as its only error handling.
- A released lock screen controller now reliably removes its handlers from the
  system-wide command center instead of leaving them behind.
- A hanging cloud provider no longer blocks an import indefinitely. The
  coordinated read of a file had no time limit and stopped noticing "Cancel";
  both now apply during the read. Progress extends the deadline, so a slow
  provider still completes.

## iPad

- On wide screens the app shows two columns: the library on the left, the
  running playback on the right. You browse for a track and still see what is
  playing; the mini player bar is no longer needed there. Settings are reachable
  from a gear button in the library toolbar.
- What decides is the window width, not the device: an iPad in Slide Over keeps
  the iPhone layout with three tabs, and nothing changes on iPhone.
- The empty-library hint is no longer clipped. In the narrow column it used to
  run past both edges.

## Command line

- `savage-cli --list <folder> --play` plays a folder as a playlist, in path
  order. An unreadable or broken module is reported and skipped; if none can be
  played, the run exits with code 1.
- On a terminal, single keys control playback: space or `p` pauses and resumes,
  `n` or arrow right skips to the next track, `b` or arrow left goes back, and
  `q` ends playback. Without a terminal (pipe, cron, CI) playback runs to the
  end as before.
- Ctrl-C stops `--play` again. Playback used to continue to the end despite the
  signal, although the status message promised otherwise. The audio output is
  now closed and the process exits with code 130.
- `--list` together with an input file is rejected instead of half-executed.
  Previously `--list` won and the given file disappeared silently.

## Archives

- `.zip` is now unpacked by the project-owned reader on every platform instead
  of the system `bsdtar`. Its safety filter therefore applies on Mac and Linux
  too: zip slip, symbolic links, encrypted entries, Zip64 and implausible
  compression ratios invalidate the **whole** archive instead of being partially
  unpacked. As a side effect only module files and nested archives are written
  to disk instead of the complete contents.
- **Behaviour change:** a ZIP containing a symbolic link is rejected entirely.
  Previously `bsdtar` unpacked the rest on Mac and Linux and only skipped the
  link.
- `bsdtar` has become optional: it is only needed for `.7z`. Building on Linux
  needs `zlib1g-dev` for the reader.
- A named pipe with a `.zip` extension no longer hangs the reader. It opens
  without blocking and rejects anything that is not a regular file.

## Modules

- XM: `P00` continues a running panning slide instead of cutting it off.
  FastTracker 2 remembers the last `Pxy` parameter; this was the only XM effect
  memory still missing.

## Linux

- The player can be installed on the desktop: `bash linux/install.sh` puts
  `savage-cli` and a menu entry into `~/.local` (no root needed, `--uninstall`
  removes them again). It then appears as the application for MOD, S3M, XM and
  IT files. The entry starts in a terminal because the keyboard controls need
  one.
- `bash linux/build-static.sh` builds a statically linked `savage-cli` in a
  container. It runs without an installed Swift runtime on the target machine.
