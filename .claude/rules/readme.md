# README

- Before making a README change part of a task, ask whether the reader would otherwise miss something the work does not show and get it wrong. If not, leave the README alone. In Issue #27 a README note was planned in without asking, and all of it was reverted: `./setup.sh` already said what had to be done by hand, and the reason for the key choice was not something a reader would want to undo.
- A manual step belongs here only when the apply cannot say it itself, as with installing the font on Windows.
- Keep config values (font names, colors, theme names, key byte sequences) out of it and write the intent instead. The same value kept in two places goes stale here first.
