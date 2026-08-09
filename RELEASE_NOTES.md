Savage Mod Player 1.6.6 hardens recursive archive imports, removes two
cross-thread playback races, and closes the remaining XM truncation paths.

## Library and archives

- Recursive imports now share one limit for uncompressed bytes, archive
  entries, and archive count across the complete nesting tree. The limits apply
  to both the native ZIP reader and the bsdtar path on macOS/Linux; inner
  archives can no longer restart with a fresh 2 GiB/50,000-entry allowance.
- bsdtar archives are measured in a streaming preflight before files are
  written. Symbolic links are rejected before directory or extension
  classification, so a staged `inner.zip` cannot point outside the extraction
  directory.
- Hidden supported modules and nested archives are processed instead of being
  silently skipped. A source archive is still removed only after every
  supported item has been handled successfully.
- An incomplete rescan after a partially failed library reset is reported as
  incomplete. The iPhone app merges its partial archive result with the known
  pending list instead of replacing that list with missing data.

## Playback correctness

- The pending elapsed-frame reset is a lock-free C11 atomic sentinel and is
  consumed exactly once with an atomic exchange. This remains available on the
  supported macOS 13 baseline and on Linux.
- End-of-song frame, position, and row are published as a complete atomic
  snapshot before the readiness signal. The UI cannot observe an old or
  half-written loop target.
- Track loop mode on macOS now resets the displayed elapsed time at the actual
  loop point and immediately refreshes system Now Playing information, matching
  the iPhone app.
- XM song playback and instrument preview use the same clamped 0...119 note
  rule before calculating either linear or Amiga periods, including extreme
  signed sample transpositions.

## Parser and release hygiene

- The XM parser requires the complete fixed 80-byte header, every declared
  pattern header even when its data size is zero, every declared instrument
  header, sample headers of at least 40 bytes, and the complete declared PCM
  window. Odd byte lengths for 16-bit samples are rejected.
- The publication hygiene gate inventories every tracked UTF-8 text file,
  including Swift, JavaScript, HTML, JSON, and CI YAML, rather than only
  Markdown, shell, and Python files.
- The optional ZIP Digital Signature record is documented correctly as being
  at the end of the ZIP central directory.
