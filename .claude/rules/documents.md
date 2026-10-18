# Documents: README, issues, PR descriptions and replies

Write only what the reader cannot get from the work itself (the diff, the config files, what `./setup.sh` prints) and would get wrong without: the reason behind a choice, a constraint found by investigating, the answer to a question.

- Before making a README change part of a task, ask whether such a thing exists. If none does, leave the README alone. A step that only "keeps the README up to date" is not a reason. In Issue #27 a README note was planned in without asking, and all of it was reverted: `./setup.sh` already said what had to be done by hand, and the reason for the key choice was not something a reader would want to undo.
- A manual step belongs in the README only when `./setup.sh` cannot say it itself, as with installing the font on Windows.
- Keep config values (font names, colors, theme names, key byte sequences) out of the README. Write the intent instead. The same value kept in two places goes stale in the README first.
- After writing, check each paragraph against "where in the work could the reader see this?" and delete the ones that have an answer. Length follows content: copy an existing document's structure, not its length.
