A polish release on top of 1.3.0: a reworked player UI, a dedicated instrument-preview path, and the code-review fixes from that round.

## Improved

- **Reworked scope & transport bar**: play/pause now sits on the spinning disk in the transport bar (stop/prev/next stay separate); the LED filter, hi-fi and loop toggles moved into a slim strip below the scopes. The **channel scopes are now adaptive-width** (available width ÷ channel count, scrolling once they hit their minimum) — up to 16 channels fit side by side at once, and the VU meter shrinks along with them.
- **Tighter tracker grid**: compact row height, 1-pt channel separators, cells hugging their content, and an automatic 1-point font reduction before a horizontal scrollbar would appear. The **row-number column is now frozen** (no longer scrolls away), and the grid has its own **discreet grey horizontal scrollbar** pinned to the bottom of the visible area.
- **Bigger click targets**: the whole instrument row (minus the download button) and the PLAYLIST/INSTRUMENTS tabs are now fully clickable.
- **Recursive `audio/` loading**: modules in subfolders (e.g. `audio/Artist/song.mod`) are found automatically, and leftover temp copies from earlier runs are cleaned up on launch.

## Fixed

- **Instrument preview** now has its own playback path, separate from the song (dedicated preview engine and channel). It plays even while the player is stopped and no longer hijacks a song channel — which previously caused a silent loss of mute/solo state.
- **Resume last played track**: with shuffle off, the previously played title is picked up again after a restart.

## Notes

- The HTML5 single-file player intentionally stays a compact 4-channel ProTracker player.
- The DMG contains the app including the Quick Look plugin; no module files are bundled. Songs are loaded via drag & drop or from a local `audio/` folder.
