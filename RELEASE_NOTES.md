Savage Mod Player 1.6.8 fixes concurrency, archive-safety and truncated-file
handling defects found by the follow-up review of the 1.6.7 QA pass.

## Playback

- Seeking during live playback is now handed to the audio callback as a
  preallocated lock-free request. Position, row, timing, effects and voices can
  no longer be observed halfway through a seek.
- After a track loop, the displayed and lock-screen time includes the audio
  frames already rendered since the exact loop transition. It no longer trails
  playback by up to one interface polling interval on every loop.

## Modules

- MOD and 15-sample Soundtracker files must contain every declared pattern and
  sample byte. Truncated files are rejected instead of being padded with silent
  notes or shortened PCM data.
- S3M sample data is validated against its declared frame count, bit depth and
  stereo layout before decoding. Truncated samples are no longer loaded as
  shorter or empty instruments.
- The first S3M end marker now terminates the order list. Orders after it are no
  longer played, and position jumps into that tail lead to song end.
- The browser player rejects a signed MOD whose song length is zero with a
  finite parser error instead of repeatedly failing in the audio worklet.

## Archives and library

- The desktop playlist scanner ignores symbolic links produced while unpacking
  an archive. A linked module or nested archive can no longer lead the scan
  outside its temporary extraction directory.
- The iOS ZIP reader rejects symbolic links and encrypted entries throughout
  the central directory, even when a file filter would otherwise skip them.
- An incomplete iOS filesystem scan now adds newly found archives to the known
  pending list while retaining older entries. A readable archive no longer
  remains invisible merely because another subtree could not be enumerated.

## Checks and tooling

- A named iOS simulator is resolved to its UUID, so a selected device from an
  older installed runtime is accepted instead of being forced to `OS:latest`.
- Command-line tests now reach and verify the real missing-value branches for
  `--seconds`, `--rate` and `--pattern`.
- Browser parser boundary tests run in CI, alongside the existing worklet
  parity and generated-HTML checks.
